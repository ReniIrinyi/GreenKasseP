using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using GreenKasse.Updater.Models;
using Microsoft.Extensions.Configuration;

namespace GreenKasse.Updater.Services;

public class SessionService
{
    private readonly string _filePath;

    public SessionService(IConfiguration cfg)
    {
        var sessionDir = cfg["Paths:Session"] ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "GreenKasse", "session");
        Directory.CreateDirectory(sessionDir);
        _filePath = Path.Combine(sessionDir, "session.bin");
    }

    public void Save(SessionData session)
    {
        var json  = JsonSerializer.Serialize(session);
        var plain = Encoding.UTF8.GetBytes(json);
        var prot  = ProtectedData.Protect(plain, null, DataProtectionScope.CurrentUser);
        File.WriteAllBytes(_filePath, prot);
    }

    public SessionData? Load()
    {
        if (!File.Exists(_filePath)) return null;
        var prot  = File.ReadAllBytes(_filePath);
        var plain = ProtectedData.Unprotect(prot, null, DataProtectionScope.CurrentUser);
        return JsonSerializer.Deserialize<SessionData>(plain);
    }

    public void Clear()
    {
        if (File.Exists(_filePath)) File.Delete(_filePath);
    }
}