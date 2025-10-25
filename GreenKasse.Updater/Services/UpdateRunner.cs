using GreenKasse.Updater.Jobs;

namespace GreenKasse.Updater.Services;

using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;


public sealed class UpdaterRunner
{
    private readonly IEnumerable<IUpdateJob> _jobs;
    private readonly IConfiguration _cfg;
    private readonly ILogger<UpdaterRunner> _log;

    public UpdaterRunner(IEnumerable<IUpdateJob> jobs, IConfiguration cfg, ILogger<UpdaterRunner> log)
        => (_jobs, _cfg, _log) = (jobs, cfg, log);

    public async Task RunOnceAsync(string[] args, CancellationToken ct)
    {
        var enabledByConfig = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var jobsSection = _cfg.GetSection("Updater:Jobs");
        foreach (var s in jobsSection.GetChildren())
        {
            if (bool.TryParse(s.Value, out var on) && on)
                enabledByConfig.Add(s.Key); 
        }

        var only = ParseListArg(args, "--only");     
        var exclude = ParseListArg(args, "--exclude"); 
        var dryRun    = args.Any(a => a.Equals("--dry-run", StringComparison.OrdinalIgnoreCase));
        var noDl      = args.Any(a => a.Equals("--no-download", StringComparison.OrdinalIgnoreCase));
        var preview   = args.Any(a => a.Equals("--preview", StringComparison.OrdinalIgnoreCase));
        var ctx       = new RunContext(dryRun, noDl, preview);
        
        var selected = _jobs
            .Where(j => enabledByConfig.Contains(j.Name))   
            .Where(j => only is null || only.Contains(j.Name, StringComparer.OrdinalIgnoreCase))
            .Where(j => exclude is null || !exclude.Contains(j.Name, StringComparer.OrdinalIgnoreCase))
            .ToList();

        if (!selected.Any())
        {
            return;
        }

        _log.LogInformation("Jobs to run: {Jobs}", string.Join(", ", selected.Select(j => j.Name)));

        var actions = new List<UpdateAction>();

        foreach (var job in selected)
        {
            try
            {
                var act = await job.RunAsync(ctx,ct);  
                if (act != null) actions.Add(act);
            }
            catch (HttpRequestException httpEx) when (IsAuthError(httpEx))
            {
                _log.LogWarning(httpEx, "Auth fehler: {Job}. Skip.", job.Name);
            }
            catch (Exception ex)
            {
                _log.LogError(ex, "Job fehler: {Job}", job.Name);
            }
        }

        if (actions.Count == 0)
        {
            return;
        }
        
        if (dryRun)
        {
            return;
        }

        var cache = _cfg["Paths:Cache"]!;
        Directory.CreateDirectory(cache);
        var planPath = Path.Combine(cache, "update.plan.json");
        var tmp = planPath + ".part";

        var plan = new
        {
            version = DateTimeOffset.UtcNow.ToString("O"),
            actions = actions.Select(a => new {
                type = a.Type, dataset = a.Key, version = a.Version,
                mode = a.Mode, path = a.Path, checksum = a.Checksum, signature = a.Signature
            }).ToArray()
        };
        
        if (preview)
        {
            var previewJson = System.Text.Json.JsonSerializer.Serialize(
                plan, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
            _log.LogInformation("PREVIEW plan:\n{Json}", previewJson);
        }

        var json = System.Text.Json.JsonSerializer.Serialize(plan, new System.Text.Json.JsonSerializerOptions{ WriteIndented = true });
        await File.WriteAllTextAsync(tmp, json, ct);
        File.Move(tmp, planPath, true);

        _log.LogInformation("Plan done: {Path}", planPath);
    }

    private static string[]? ParseListArg(string[] args, string name)
    {
        var kv = args.FirstOrDefault(a => a.StartsWith(name + "=", StringComparison.OrdinalIgnoreCase));
        return kv is null ? null : kv[(name.Length + 1)..].Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    }

    private static bool IsAuthError(HttpRequestException ex)
        => ex.Message.Contains("401") || ex.Message.Contains("403");
}
