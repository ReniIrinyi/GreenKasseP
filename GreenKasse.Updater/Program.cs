using GreenKasse.Updater.Jobs;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using GreenKasse.Updater.Services;

var services = new ServiceCollection();
var configPath = Path.Combine(AppContext.BaseDirectory, "..", "..", "appsettings.shared.json");
configPath = Path.GetFullPath(configPath);
var configuration = new ConfigurationBuilder()
    .AddJsonFile(configPath, optional: false, reloadOnChange: true)
    .Build();


services.AddSingleton<IConfiguration>(configuration);
services.AddSingleton<CloudClient>();
services.AddLogging(b => { b.AddConsole(); b.SetMinimumLevel(LogLevel.Information); });

services.AddSingleton<IUpdateJob, ArtikelstammJob>();
// services.AddSingleton<IUpdateJob, KassenconfigJob>();
// services.AddSingleton<IUpdateJob, UserconfigJob>();
// services.AddSingleton<IUpdateJob, KundenDatenJob>();
// services.AddSingleton<IUpdateJob, PwaJob>();
// services.AddSingleton<IUpdateJob, DbStrukturJob>();

services.AddSingleton<UpdaterRunner>();


using var provider = services.BuildServiceProvider();
var log    = provider.GetRequiredService<ILogger<Program>>();
var auth  = provider.GetRequiredService<CloudAuth>();
var runner= provider.GetRequiredService<UpdaterRunner>();
var ct     = CancellationToken.None;


var opts = CliOptions.Parse(args);

if (opts.ShowHelp)
{
    PrintHelp();
    return;
}

if (opts.ClearSession)
{
    provider.GetRequiredService<SessionService>().Clear();
    log.LogInformation("Session cleared.");
    if (opts.LoginOnly == false && opts.Only?.Length == 0 && opts.Exclude?.Length == 0) return;
}

if (opts.Setup)
{
    try { _ = provider.GetRequiredService<Creditentials>().Load(); }
    catch (Exception ex) { log.LogError(ex, "Setup / cred loading failed."); }
    return;
}

await auth.EnsureAsync(ct);

if (opts.LoginOnly)
{
    return;
}

await runner.RunOnceAsync(args, ct);
log.LogInformation("Done.");

static void PrintHelp()
{
    Console.WriteLine("""
GreenKasse.Updater 
  --only=J1,J2        nur aufgelistete Jobs (Artikelstamm,Pwa)
  --exclude=J1,J2     ausgenommen aufgelistete Jobs
  --dry-run           jobs werdenausgeführt, plan.json nicht geschrieben (test)
  --dry-run --no-download plan als liste erstellen, ohne download (test)
  --login-only        kein job-run, nur auth
  --clear-session     clear a DPAPI session.bin-t 
  --setup             cred check / run setup.exe (wenn kein cred)

Jobs: Artikelstamm, KassenConfig, UserConfig, KundenDaten, Pwa, DbStruktur
""");
}

public sealed record CliOptions(
    string[]? Only,
    string[]? Exclude,
    bool DryRun,
    bool LoginOnly,
    bool ClearSession,
    bool Setup,
    bool ShowHelp)
{
    public static CliOptions Parse(string[] args)
    {
        string[]? only = GetList(args, "--only");
        string[]? exclude = GetList(args, "--exclude");
        bool dry = Has(args, "--dry-run");
        bool loginOnly = Has(args, "--login-only");
        bool clearSession = Has(args, "--clear-session");
        bool setup = Has(args, "--setup");
        bool help = Has(args, "--help") || Has(args, "-h") || Has(args, "/?");
        return new(only, exclude, dry, loginOnly, clearSession, setup, help);
    }

    static bool Has(string[] a, string flag) => a.Any(x => x.Equals(flag, StringComparison.OrdinalIgnoreCase));

    static string[]? GetList(string[] a, string key)
    {
        var kv = a.FirstOrDefault(x => x.StartsWith(key + "=", StringComparison.OrdinalIgnoreCase));
        return kv is null
            ? null
            : kv[(key.Length + 1)..].Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    }
}

