using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;

namespace GreenKasse.Infrastructure.System;

public sealed class CredentialService : ICredentialService
{
    private readonly string _filePath;
    private readonly string _sessionDir;
    private readonly IConfiguration _cfg;

    public CredentialService(IConfiguration cfg) 
    {
        _cfg = cfg;

        _sessionDir = _cfg["Paths:Session"]
                      ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                                      "GreenKasse", "session");
        Directory.CreateDirectory(_sessionDir);

        _filePath = Path.Combine(_sessionDir, "cloud.creds.bin");
    }

    public CloudCreditentials Load()             
    {
        if (!File.Exists(_filePath))
        {
            Console.WriteLine("⚠️ Keine Cloud-Zugangsdaten gefunden.");

            var autoLaunch = _cfg.GetValue("Setup:AutoLaunch", true);
            var setupExe   = _cfg["Setup:ExePath"]
                             ?? Path.Combine(AppContext.BaseDirectory, "GreenKasse.Setup.exe");

            if (autoLaunch && File.Exists(setupExe))
            {
                Console.WriteLine("Setup wird gestartet…");
                var psi = new ProcessStartInfo(setupExe) { UseShellExecute = true };
                using var p = Process.Start(psi);
                p?.WaitForExit();

                if (!File.Exists(_filePath))
                    throw new FileNotFoundException($"Setup wurde ausgeführt, aber Datei fehlt: {_filePath}");
            }
            else
            {
                var reason = autoLaunch
                    ? $"Setup.exe nicht gefunden unter: {setupExe}"
                    : "AutoLaunch deaktiviert (Setup:AutoLaunch=false).";
                throw new InvalidOperationException($"Cloud-Setup konnte nicht ausgeführt werden. {reason}");
            }
        }

        var protectedBytes = File.ReadAllBytes(_filePath);

        var useMachineScope = _cfg.GetValue("Security:UseMachineScope", false);
        var scope = useMachineScope ? DataProtectionScope.LocalMachine : DataProtectionScope.CurrentUser;

        var plain = ProtectedData.Unprotect(protectedBytes, null, scope);

        var creds = JsonSerializer.Deserialize<CloudCreditentials>(plain);
        if (creds is null)
            throw new InvalidDataException("cloud.creds.bin ist beschädigt oder leer.");

        return creds;
    }

    public void Clear()
    {
        if (File.Exists(_filePath)) File.Delete(_filePath);
    }

    public void SaveEncrypted(CloudCreditentials creds)
    {
        var json = JsonSerializer.Serialize(creds);
        var plainBytes = Encoding.UTF8.GetBytes(json);

        var useMachineScope = _cfg.GetValue("Security:UseMachineScope", false);
        var scope = useMachineScope ? DataProtectionScope.LocalMachine : DataProtectionScope.CurrentUser;

        var protectedBytes = ProtectedData.Protect(plainBytes, null, scope);
        File.WriteAllBytes(_filePath, protectedBytes);
    }

    public CloudCreditentials LoadFile()          // ← visszatérési típus
    {
        var bytes = File.ReadAllBytes(_filePath);

        var useMachineScope = _cfg.GetValue("Security:UseMachineScope", false);
        var scope = useMachineScope ? DataProtectionScope.LocalMachine : DataProtectionScope.CurrentUser;

        var plain = ProtectedData.Unprotect(bytes, null, scope);
        return JsonSerializer.Deserialize<CloudCreditentials>(plain)!;
    }
}
