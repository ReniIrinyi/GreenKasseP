using System.Text;
using System.Text.Json;
using GreenKasse.Setup.Models;
using System.Security.Cryptography;

public class CreditentialService
{
    private const string FilePath = @"C:\ProgramData\GreenKasse\session\cloud.creds.bin";

    public void SaveEncrypted(CloudCreditentials creds)
    {
        var json = JsonSerializer.Serialize(creds);
        var plainBytes = Encoding.UTF8.GetBytes(json);
        var protectedBytes = ProtectedData.Protect(plainBytes, null, DataProtectionScope.CurrentUser);
        File.WriteAllBytes(FilePath, protectedBytes);
    }

    public CloudCreditentials Load()
    {
        var bytes = File.ReadAllBytes(FilePath);
        var plain = ProtectedData.Unprotect(bytes, null, DataProtectionScope.CurrentUser);
        return JsonSerializer.Deserialize<CloudCreditentials>(plain)!;
    }
}