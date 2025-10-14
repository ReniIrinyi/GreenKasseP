using System.Text;


public class EscPosService
{
    private readonly string? _preferredPrinter;
    private readonly IConfiguration _cfg;

    public EscPosService(IConfiguration cfg)
    {
        _cfg = cfg;
        _preferredPrinter = _cfg["Devices:PrinterName"];
    }

    public void PrintText(string text, bool cut = true, bool openDrawerAfter = false)
    {
        var init = new byte[] { 0x1B, 0x40 }; // ESC @
        var data = Encoding.UTF8.GetBytes(text.Replace("\r\n", "\n").Replace("\r", "\n"));
        var lf   = new byte[] { 0x0A };

        var buf = new List<byte>(init.Length + data.Length + lf.Length + 16);
        buf.AddRange(init);
        buf.AddRange(data);
        buf.AddRange(lf);

        if (openDrawerAfter) buf.AddRange(DrawerPulse());
        if (cut) buf.AddRange(new byte[] { 0x1D, 0x56, 0x42, 0x00 }); // GS V B 0
        
        RawPrinter.Send(_preferredPrinter, buf.ToArray());
    }

    public void OpenDrawer()
    {
        var viaPrinter = bool.TryParse(_cfg["Devices:CashDrawer:OpenViaPrinter"], out var v) && v;

        if (viaPrinter)
        {
            try
            {
                RawPrinter.Send(_preferredPrinter, DrawerPulse());
                return;
            }
            catch
            {
            }
        }

        OpenDrawerOnCom();
    }

    private static byte[] DrawerPulse()
    {
        // ESC p m t1 t2   (m=0 | 1)
        var t1 = (byte)100;
        var t2 = (byte)100;
        return new byte[] { 0x1B, 0x70, 0x00, t1, t2 };
    }

    private void OpenDrawerOnCom()
    {
        var port = _cfg["Devices:CashDrawer:ComPort"] ?? "COM1";
        var pulseOn  = int.TryParse(_cfg["Devices:CashDrawer:PulseOnMs"], out var pon) ? pon : 100;
        var pulseOff = int.TryParse(_cfg["Devices:CashDrawer:PulseOffMs"], out var poff) ? poff : 100;

        using var sp = new System.IO.Ports.SerialPort(port, 9600, System.IO.Ports.Parity.None, 8, System.IO.Ports.StopBits.One);
        sp.Open();
        sp.Write(new byte[] { 0x1B, 0x70, 0x00, (byte)pulseOn, (byte)pulseOff }, 0, 5);
        sp.Close();
    }
}
