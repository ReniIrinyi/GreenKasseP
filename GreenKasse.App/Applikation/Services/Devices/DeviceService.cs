
public sealed class DeviceService
{
    public string GetId() => DeviceIdProvider.GetDeviceId();
}