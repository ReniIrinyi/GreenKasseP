using System.Runtime.Versioning;
using System.Text;
using GreenKasse.Devices.Dto;
using Microsoft.Extensions.Configuration;

[SupportedOSPlatform("windows")]
public sealed class EscPosBonPrinter : IBonPrinter
{
    private readonly IConfiguration _cfg;
    private readonly string? _preferredPrinter;
    private readonly ICashDrawer _drawer;
    private DeviceStatus _status = DeviceStatus.Stopped;

    public EscPosBonPrinter(IConfiguration cfg, ICashDrawer drawer)
    {
        _cfg = cfg;
        _drawer = drawer;
        _preferredPrinter = _cfg["Devices:PrinterName"];
    }

    public void Start()
    {
        _status = DeviceStatus.Starting;
        try
        {
            RawPrinterWinSpool.SendOrThrow(_preferredPrinter!, new byte[] { 0x1B, 0x40 }); // ESC @
            _status = DeviceStatus.Ready;
        }
        catch
        {
            _status = DeviceStatus.Error;
            throw;
        }
    }

    public void Stop() => _status = DeviceStatus.Stopped;
    public DeviceStatus GetStatus() => _status;

    public PrintStatus Print(Bon bon)
    {
        try
        {
            var text = bon.Text ?? string.Empty;
            var buf = new List<byte>(text.Length + 64);
            buf.AddRange(new byte[] { 0x1B, 0x40 }); // init
            buf.AddRange(SetCodePage(_cfg["Devices:Printer:CodePage"]));

            var normalized = text.Replace("\r\n", "\n").Replace('\r', '\n');
            var enc = GetEncoding(_cfg["Devices:Printer:CodePage"]);
            buf.AddRange(enc.GetBytes(normalized));
            buf.Add(0x0A); // LF

            if (bon.OpenDrawerAfter) buf.AddRange(new byte[] { 0x1B, 0x70, 0x00, 100, 100 });
            if (bon.Cut) buf.AddRange(new byte[] { 0x1D, 0x56, 0x42, 0x00 });

            RawPrinterWinSpool.SendOrThrow(_preferredPrinter!, buf.ToArray());
            return PrintStatus.Ok;
        }
        catch (PrinterNotAvailableException)
        {
            throw; 
        }
        catch
        {
            _status = DeviceStatus.Error;
            return PrintStatus.Error;
        }
    }

    private static IEnumerable<byte> SetCodePage(string? cp)
    {
        byte n = cp?.Trim() switch
        {
            "437" or "CP437" => 0,
            "858" or "CP858" or "Latin9" => 17,
            "852" or "CP852" => 18,
            _ => 0
        };
        return new byte[] { 0x1B, 0x74, n };
    }

    private static Encoding GetEncoding(string? cp)
    {
        try
        {
            return cp?.Trim() switch
            {
                "858" or "CP858" => Encoding.GetEncoding(858),
                "852" or "CP852" => Encoding.GetEncoding(852),
                _ => Encoding.GetEncoding(437)
            };
        }
        catch
        {
            return Encoding.GetEncoding(437);
        }
    }
}
