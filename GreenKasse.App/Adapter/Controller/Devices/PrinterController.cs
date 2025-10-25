
using Microsoft.AspNetCore.Mvc;
using GreenKasse.App.Applikation.Dto;
using GreenKasse.App.Applikation.Services;
using GreenKasse.App.Domain.Errors;


public sealed class PrinterController : IController
{
    public void Map(IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/print");

        group.MapPost("/", async (
            [FromServices] ReceiptService svc,
            [FromBody] PrintReceiptDto dto,
            CancellationToken ct) =>
        {
            try
            {
                await svc.PrintAsync(dto, ct);
                return Results.Ok(new { printed = true });
            }
            catch (DomainException ex)
            {
                return Results.Problem(title: "Print failed", detail: ex.Message, statusCode: 412);
            }
        });
    }
}