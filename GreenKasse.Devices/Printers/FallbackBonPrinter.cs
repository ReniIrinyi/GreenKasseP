using GreenKasse.Devices.Dto;

public sealed class FallbackBonPrinter : IBonPrinter
{
    private readonly EscPosBonPrinter _escPos;
    public FallbackBonPrinter(EscPosBonPrinter escPos)
    {
        _escPos = escPos;
    }

    public void Start() { }
    public void Stop() { }
    public DeviceStatus GetStatus() => DeviceStatus.Ready;

    public PrintStatus Print(Bon bon)
    {
        try
        {
            return _escPos.Print(bon);
        }
        catch (PrinterNotAvailableException)
        {
            WindowsPrinter.PrintText(bon.Text ?? string.Empty);
            return PrintStatus.Ok;
        }
    }
}
