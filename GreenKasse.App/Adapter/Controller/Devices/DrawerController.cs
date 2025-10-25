
using Microsoft.AspNetCore.Mvc;
using GreenKasse.App.Applikation.Services;
using GreenKasse.App.Domain.Errors;

public sealed class DrawerController : IController
{
    public void Map(IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/printer");

        group.MapPost("/print", async (
            [FromServices] DrawerService svc,
            CancellationToken ct) =>
        {
            try
            {
                await svc.OpenAsync(ct);
                return Results.Ok(new { ok = true });
            }
            catch (DomainException ex)
            {
                return Results.Problem(title: "Drawer open failed", detail: ex.Message, statusCode: 403);
            }
        });
    }
}