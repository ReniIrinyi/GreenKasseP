using Microsoft.AspNetCore.Mvc;
using GreenKasse.App.Applikation.Dto;
using GreenKasse.App.Applikation.Services;
using GreenKasse.App.Applikation.Services.Auth;

namespace GreenKasse.App.Adapter.Controller.Auth;

public sealed class LoginController : IController
{
    public void Map(IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api");

        group.MapPost("/login", async (
            [FromServices] LoginService svc,
            [FromBody] LoginRequest dto,
            CancellationToken ct) =>
        {
            var result = await svc.LoginAsync(dto, ct);
            return Results.Json(result);
        });
    }
}