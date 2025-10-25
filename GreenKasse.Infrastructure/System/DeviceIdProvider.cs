using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32;

public sealed class DeviceIdProvider
{
    private static readonly object _lock = new();
    private static string? _cached;
    private const string Prefix = "GK-";
    private static readonly string StorePath =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                     "GreenKasse", "deviceid.bin");

    public static string GetDeviceId()
    {
        if (_cached is not null) return _cached;
        lock (_lock)
        {
            if (_cached is not null) return _cached;

            var id = TryMachineGuid() ?? TryLoadOrCreatePersistentId();
            id = Normalize(id);

            _cached = Prefix + id;
            return _cached;
        }
    }

    private static string? TryMachineGuid()
    {
        try
        {
            using var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
            using var key = baseKey.OpenSubKey(@"SOFTWARE\Microsoft\Cryptography", false);
            var v = key?.GetValue("MachineGuid") as string;
            if (string.IsNullOrWhiteSpace(v)) return null;

            v = v.Trim().Trim('{', '}');
            return v;
        }
        catch
        {
            return null;
        }
    }

    private static string TryLoadOrCreatePersistentId()
    {
        try
        {
            if (File.Exists(StorePath))
            {
                var enc = File.ReadAllBytes(StorePath);
                var raw = ProtectedData.Unprotect(enc, null, DataProtectionScope.CurrentUser);
                return Encoding.UTF8.GetString(raw);
            }
        }
        catch
        {
        }

       
        var guid = Guid.NewGuid().ToString();
        try
        {
            var raw = Encoding.UTF8.GetBytes(guid);
            var enc = ProtectedData.Protect(raw, null, DataProtectionScope.CurrentUser);

            Directory.CreateDirectory(Path.GetDirectoryName(StorePath)!);
            File.WriteAllBytes(StorePath, enc);
        }
        catch
        {
        }

        return guid;
    }

    private static string Normalize(string id)
    {
        var cleaned = id.Replace("-", "").Replace("{", "").Replace("}", "").ToUpperInvariant();
        return cleaned;
    }
}
