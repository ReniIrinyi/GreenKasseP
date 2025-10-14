
using System.Management;
public class DeviceProvider
{
    public string GetDeviceId()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT UUID FROM Win32_ComputerSystemProduct");
            var collection = searcher.Get();
            foreach (var item in collection)
            {
                var uuid = item["UUID"]?.ToString()?.ToUpperInvariant();
                if (!string.IsNullOrEmpty(uuid))
                    return $"GK-{uuid}";
            }
        }
        catch
        {
            return $"GK-UNKNOWN-{Environment.MachineName}";
        }

        return "GK-UNKNOWN";
    }

}
