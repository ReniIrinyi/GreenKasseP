using System.Runtime.InteropServices;


public class WinSpoolPrinter
{
    [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern bool GetDefaultPrinter(System.Text.StringBuilder pszBuffer, ref int pcchBuffer);

    public static string? GetDefaultPrinterName()
    {
        int len = 0;
        GetDefaultPrinter(null!, ref len); 
        if (len <= 0) return null;

        var sb = new System.Text.StringBuilder(len);
        return GetDefaultPrinter(sb, ref len) ? sb.ToString() : null;
    }
}