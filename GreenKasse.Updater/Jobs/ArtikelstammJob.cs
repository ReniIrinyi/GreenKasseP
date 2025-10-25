using GreenKasse.Updater.Services;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace GreenKasse.Updater.Jobs;

public sealed class ArtikelstammJob(
    IConfiguration cfg,
    CloudClient cloud,
    CloudAuth auth,
    ILogger<ArtikelstammJob> log) : IUpdateJob
{
    public string Name => "Artikelstamm";

    public async Task<UpdateAction?> RunAsync(RunContext ctx,CancellationToken ct)
    {
        if (!cfg.GetValue("Updater:Jobs:Artikelstamm", true)) return null;

        var p = cfg.GetSection("CloudPaths");
        var relative = $"{p["Path"]}{p["Sync"]}{p["Artikelstamm"]}";

        var cache = cfg["Paths:Cache"]!;
        var ver   = DateTimeOffset.UtcNow.ToString("yyyy-MM-ddTHH-mm-ssZ");
        var dir   = Path.Combine(cache, "datasets", "artikel", $"v{ver}");
        Directory.CreateDirectory(dir);

        var finalPath = Path.Combine(dir, "artikel.parquet");
        string sha = ""; 
        if (ctx.NoDownload)
        {
            log.LogInformation("[NoDownload] Skip download: {Url}",relative);
        }
        else
        {
            log.LogInformation("Download Artikelstamm: {Url}", relative);

            var res  = await auth.ExecuteWithAuthAsync(
                _ => cloud.DownloadAsync(relative, finalPath, ct), ct);
            sha = res.sha256; 
            await File.WriteAllTextAsync(Path.Combine(dir, "READY.ok"), ver, ct);
        }
        

        var rel = Path.GetRelativePath(cache, finalPath).Replace('\\', '/');
        log.LogInformation("Artikelstamm done: {Path} (sha256={Sha})", rel, sha);

        return new UpdateAction(
            Type: "data",
            Key: "artikel",
            Version: ver,
            Path: rel,
            Mode: "replace",
            Checksum: "sha256:" + sha
        );
    }
}
