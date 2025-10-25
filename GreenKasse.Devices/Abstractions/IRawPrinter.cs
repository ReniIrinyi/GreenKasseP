public interface IRawPrinter
{
    void Send(string? preferredPrinterName, byte[] raw);
}

public sealed class RawPrinterWinSpoolAdapter : IRawPrinter
{
    public void Send(string? preferredPrinterName, byte[] raw)
        => RawPrinterWinSpool.SendOrThrow(preferredPrinterName, raw);
}