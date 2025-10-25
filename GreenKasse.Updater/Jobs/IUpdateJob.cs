namespace GreenKasse.Updater.Jobs;

public interface IUpdateJob
{
    string Name { get; }
    Task<UpdateAction?> RunAsync(RunContext ctx,CancellationToken ct); 
}

public sealed record UpdateAction(
    string Type,       // "data" | "config" | "app" | "schema"
    string Key,        // "artikel" | "kasseconfig" | "pwa" | ...
    string Version,    // UTC ts vagy semver
    string Path,       // cache relative pfad
    string Mode = "replace",
    string? Checksum = null,
    string? Signature = null
);


public sealed record RunContext(bool DryRun, bool NoDownload, bool Preview);
