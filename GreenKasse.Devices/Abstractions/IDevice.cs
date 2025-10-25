
    using GreenKasse.Devices.Dto;

    public interface IDevice
    {
        void Start();
        void Stop();
        DeviceStatus GetStatus(); 
    }
