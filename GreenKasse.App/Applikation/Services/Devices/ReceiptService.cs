using GreenKasse.App.Applikation.Dto;
using GreenKasse.App.Domain.Errors;
using GreenKasse.Devices.Dto;

public class ReceiptService
{
    private readonly IBonPrinter _printer;

    public ReceiptService(IBonPrinter printer) => _printer = printer;

    public async Task PrintAsync(PrintReceiptDto dto, CancellationToken ct)
    {
        var header = $"GreenKasse POS  •  {DateTime.Now:yyyy-MM-dd HH:mm}\n";
        var body   = dto.Text.Replace("\r\n", "\n");
        var payload = header + body;

        for (int i = 0; i < dto.Copies; i++)
        {
            var status = _printer.Print(new Bon(payload, dto.Cut, dto.OpenDrawerAfter));
            if (status != PrintStatus.Ok)
                throw new DomainException("Fehler");
        }

        await Task.CompletedTask;
    }
}