using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public sealed class PrinterNotAvailableException : Exception
{
    public PrinterNotAvailableException(string message) : base(message) { }
}

public static class RawPrinterWinSpool
{
    public static void SendOrThrow(string preferredPrinterName, byte[] bytes)
    {
        if (string.IsNullOrWhiteSpace(preferredPrinterName))
        {
            var def = TryGetDefaultPrinter();
            Console.WriteLine(def);
            if (string.IsNullOrWhiteSpace(def))
                throw new PrinterNotAvailableException("Kein Defaultprinter vorhanden");
            SendRawToPrinterOrThrow(def!, bytes);
            return;
        }

        if (!IsInstalled(preferredPrinterName))
        {
            var def = TryGetDefaultPrinter();
            if (!string.IsNullOrWhiteSpace(def) && IsInstalled(def!))
            {
                SendRawToPrinterOrThrow(def!, bytes);
                return;
            }
            throw new PrinterNotAvailableException($"weder Bondrucker : '{preferredPrinterName}', noch Defaultprinter vorhanden .");
        }

        SendRawToPrinterOrThrow(preferredPrinterName, bytes);
    }

    private static void SendRawToPrinterOrThrow(string printerName, byte[] bytes)
        => SendRawToPrinter(printerName, bytes);

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
        catch { }
        return false;
    }

    private static string? TryGetDefaultPrinter()
    {
        int size = 0;
        // első hívás a buffer méretéért
        GetDefaultPrinter(null!, ref size);
        if (size <= 0) return null;

        var sb = new StringBuilder(size);
        return GetDefaultPrinter(sb, ref size) ? sb.ToString() : null;
    }

    // ===== Winspool P/Invoke =====
    [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern bool GetDefaultPrinter(StringBuilder pszBuffer, ref int pcchBuffer);

    [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, ref PRINTER_DEFAULTS pDefault);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Ansi)]
    private static extern bool StartDocPrinter(IntPtr hPrinter, int level, ref DOC_INFO_1 di);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool StartPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool EndPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    struct DOC_INFO_1
    {
        [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPStr)] public string? pOutputFile;
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
            var docInfo = new DOC_INFO_1 { pDocName = "ESC/POS RAW", pOutputFile = null, pDatatype = "RAW" };
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
