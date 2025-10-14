using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Drawing.Printing;

public static class RawPrinter
{
    public static void Send(string? preferredPrinterName, byte[] bytes)
    {
        var printerName = ResolvePrinterName(preferredPrinterName);
        SendRawToPrinter(printerName, bytes);
    }

    private static string ResolvePrinterName(string? preferred)
    {
        if (!string.IsNullOrWhiteSpace(preferred) && IsInstalled(printerName: preferred!))
            return preferred!;

        var def = new PrinterSettings().PrinterName; 
        if (!string.IsNullOrWhiteSpace(def) && IsInstalled(def))
            return def;

        throw new InvalidOperationException(
            $"Nincs elérhető nyomtató. " +
            $"Configban megadott: '{preferred ?? "<null>"}', " +
            $"Windows default: '{def ?? "<null>"}'.");
    }

    private static bool IsInstalled(string printerName)
    {
        try
        {
            IntPtr hPrinter;
            var di = new PRINTER_DEFAULTS();
            if (OpenPrinter(printerName, out hPrinter, ref di))
            {
                ClosePrinter(hPrinter);
                return true;
            }
        }
        catch {  }
        return false;
    }

    // ===== Winspool P/Invoke  =====
    [DllImport("winspool.Drv", SetLastError = true, CharSet = CharSet.Auto)]
    static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, ref PRINTER_DEFAULTS pDefault);

    [DllImport("winspool.Drv", SetLastError = true)]
    static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", SetLastError = true, CharSet = CharSet.Ansi)]
    static extern bool StartDocPrinter(IntPtr hPrinter, int level, ref DOC_INFO_1 di);

    [DllImport("winspool.Drv", SetLastError = true)]
    static extern bool EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", SetLastError = true)]
    static extern bool StartPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", SetLastError = true)]
    static extern bool EndPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", SetLastError = true)]
    static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    struct DOC_INFO_1
    {
        [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPStr)] public string pDatatype; // "RAW"
    }

    [StructLayout(LayoutKind.Sequential)]
    struct PRINTER_DEFAULTS
    {
        public IntPtr pDatatype;
        public IntPtr pDevMode;
        public int DesiredAccess;
    }

    private static void SendRawToPrinter(string printerName, byte[] bytes)
    {
        IntPtr hPrinter = IntPtr.Zero;
        var di = new PRINTER_DEFAULTS();
        if (!OpenPrinter(printerName, out hPrinter, ref di))
            ThrowWin32("OpenPrinter", printerName);

        try
        {
            var docInfo = new DOC_INFO_1
            {
                pDocName = "ESC/POS RAW",
                pOutputFile = null,
                pDatatype = "RAW"
            };

            if (!StartDocPrinter(hPrinter, 1, ref docInfo)) ThrowWin32("StartDocPrinter", printerName);
            try
            {
                if (!StartPagePrinter(hPrinter)) ThrowWin32("StartPagePrinter", printerName);
                try
                {
                    var unmanagedBytes = Marshal.AllocHGlobal(bytes.Length);
                    try
                    {
                        Marshal.Copy(bytes, 0, unmanagedBytes, bytes.Length);
                        if (!WritePrinter(hPrinter, unmanagedBytes, bytes.Length, out var written) || written != bytes.Length)
                            ThrowWin32("WritePrinter", printerName);
                    }
                    finally { Marshal.FreeHGlobal(unmanagedBytes); }
                }
                finally { EndPagePrinter(hPrinter); }
            }
            finally { EndDocPrinter(hPrinter); }
        }
        finally { ClosePrinter(hPrinter); }
    }

    private static void ThrowWin32(string api, string printerName)
    {
        var err = new Win32Exception(Marshal.GetLastWin32Error());
        throw new InvalidOperationException($"{api} failed for printer '{printerName}': {err.Message}");
    }
}
