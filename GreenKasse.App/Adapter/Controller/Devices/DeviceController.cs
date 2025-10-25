using GreenKasse.App.Applikation.Services;
using GreenKasse.App.Domain.Errors;
using Microsoft.AspNetCore.Mvc;


public sealed class DeviceController : IController
{
    public void Map(IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api");

        group.MapGet("/ping", async (
        
            [FromServices] DrawerService svc,
            CancellationToken ct) =>
        {
            try
            {
                Console.WriteLine("here"); 
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