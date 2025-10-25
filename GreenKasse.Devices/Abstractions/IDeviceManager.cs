
using GreenKasse.Devices.Dto;

public interface IDeviceManager
{
    void StartAll();
    void StopAll();
    IReadOnlyDictionary<string, DeviceStatus> GetStatuses();
    T Get<T>() where T : class, IDevice; 
}