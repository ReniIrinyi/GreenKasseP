
using System.Text.Json;
using KasseApp.Server.Services;
using Microsoft.Extensions.FileProviders;
using Microsoft.AspNetCore.Mvc;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddCors(options =>
{
    options.AddPolicy("Dev", p => p
        .AllowAnyOrigin()
        .AllowAnyHeader()
        .AllowAnyMethod());
});


builder.Services.AddSingleton<CloudAuthClient>(sp =>
{
    var cfg = sp.GetRequiredService<IConfiguration>();
    return new CloudAuthClient(cfg);
});


builder.Services.AddSingleton<EscPosService>();

var app = builder.Build();
app.UseCors("Dev");


var webRoot = builder.Configuration["WebRoot"]; 
if (!string.IsNullOrWhiteSpace(webRoot) && Directory.Exists(webRoot))
{
    var provider = new PhysicalFileProvider(webRoot);
    app.UseDefaultFiles(new DefaultFilesOptions { FileProvider = provider });
    app.UseStaticFiles(new StaticFileOptions { FileProvider = provider });

    app.MapFallback(context =>
    {
        var index = Path.Combine(webRoot, "index.html");
        if (File.Exists(index))
        {
            context.Response.ContentType = "text/html; charset=utf-8";
            return context.Response.SendFileAsync(index);
        }
        context.Response.StatusCode = 404;
        return Task.CompletedTask;
    });
}
else
{
    app.Logger.LogWarning("WebRoot not found. Static files disabled.");
}

app.MapGet("/api/device-id", () =>
{
    var id = DeviceIdProvider.GetDeviceId();
    return Results.Ok(new { deviceId = id });
});


app.MapPost("/api/login", async ([FromServices] CloudAuthClient cloud,
    [FromBody] LoginDto dto, CancellationToken ct) =>
{
    var deviceId = DeviceIdProvider.GetDeviceId();

    var (sessId, shiftKey) = await cloud.GetSessionAndShiftAsync(ct); 
    await cloud.PrimeSessionAsync(sessId, ct);          

    using var doc = await cloud.LoginAsync(
        tokenId:  sessId,
        deviceId: deviceId,
        shiftKey: shiftKey,
        isTill:   true,
        user:     dto.user,
        passPlain:dto.pass,
        licence:  dto.licence,
        ct:       ct
    );

    return Results.Json(JsonSerializer.Deserialize<object>(doc.RootElement.GetRawText())!);
});



app.MapPost("/api/print", ([FromServices] EscPosService esc, [FromBody] PrintDto dto) =>
{
    esc.PrintText(dto.Text ?? "", dto.Cut, dto.OpenDrawerAfter);
    return Results.Ok(new { printed = true });
});

app.MapPost("/api/drawer/open", (EscPosService esc) =>
{
    try
    {
        esc.OpenDrawer();
        return Results.Json(new { ok = true });
    }
    catch (Exception ex)
    {
        return Results.Problem(
            title: "Drawer open failed",
            detail: ex.ToString(),
            statusCode: 500
        );
    }
});


app.Run();

record LoginDto(string user, string pass, string licence);

public record PrintDto(string Text, bool Cut = true, bool OpenDrawerAfter = false);

