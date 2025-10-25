using GreenKasse.Devices.Dto;

public sealed class DeviceManager : IDeviceManager
{
    private readonly Dictionary<Type, IDevice> _devices;

    public DeviceManager(IEnumerable<IDevice> devices)
    {
        _devices = devices.ToDictionary(d => d.GetType().GetInterfaces()
            .First(i => typeof(IDevice).IsAssignableFrom(i) && i != typeof(IDevice)));
    }

    public void StartAll() { foreach (var d in _devices.Values) Safe(() => d.Start()); }
    public void StopAll()  { foreach (var d in _devices.Values) Safe(() => d.Stop());  }

    public IReadOnlyDictionary<string, DeviceStatus> GetStatuses() =>
        _devices.Values.ToDictionary(d => d.GetType().Name, d => d.GetStatus());

    public T Get<T>() where T : class, IDevice => (T)_devices[typeof(T)];

    private static void Safe(Action a) { try { a(); } catch { /* log + isolate */ } }
}