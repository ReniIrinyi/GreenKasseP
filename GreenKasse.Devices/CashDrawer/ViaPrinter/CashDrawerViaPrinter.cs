using GreenKasse.Devices.Dto;
using Microsoft.Extensions.Configuration;

public sealed class CashDrawerViaPrinter : ICashDrawer
{
    private readonly IConfiguration _cfg;
    private DeviceStatus _status = DeviceStatus.Stopped;

    public CashDrawerViaPrinter(IConfiguration cfg) => _cfg = cfg;

    public void Start()  => _status = DeviceStatus.Ready;
    public void Stop()   => _status = DeviceStatus.Stopped;
    public DeviceStatus GetStatus() => _status;

    public void Open()
    {
        var printer = _cfg["Devices:PrinterName"];
        if (string.IsNullOrWhiteSpace(printer))
            throw new InvalidOperationException("Devices:PrinterName nicht vorhanden.");
        RawPrinterWinSpool.SendOrThrow(printer, new byte[] { 0x1B, 0x70, 0x00, 100, 100 });
    }
}