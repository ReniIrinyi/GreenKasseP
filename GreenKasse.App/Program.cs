using GreenKasse.App.Adapter.Database;
using GreenKasse.Devices.Extensions;
using Microsoft.EntityFrameworkCore;
using Pomelo.EntityFrameworkCore.MySql.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

var env = builder.Environment;
var contentRoot = env.ContentRootPath;

var cfgBase = File.Exists(Path.Combine(contentRoot, "appsettings.json"))
    ? contentRoot
    : Directory.GetParent(contentRoot)!.FullName;

builder.Configuration
    .AddJsonFile(Path.Combine(cfgBase, "appsettings.json"), optional: false, reloadOnChange: true)
    .AddJsonFile(Path.Combine(cfgBase, $"appsettings.{env.EnvironmentName}.json"), optional: true, reloadOnChange: true)
    .AddEnvironmentVariables();

var cfg = builder.Configuration;

// ---- PORT + URL bind ----
var port = cfg.GetValue("Port", 8080);
builder.WebHost.UseUrls($"http://+:{port}");

// ---- WEBROOT  ----
// "C:\\ProgramData\\GreenKasse\\wwwroot"
var webRoot = cfg["WebRoot"];
if (!string.IsNullOrWhiteSpace(webRoot) && Directory.Exists(webRoot))
{
    builder.WebHost.UseWebRoot(webRoot);
}

// ---- SERVICES / DI ----
builder.Services.AddDevices(cfg);
builder.Services.AddScoped<DrawerService>();

var cs = cfg.GetConnectionString("MariaDb")!;
var serverVersion = ServerVersion.Create(new Version(10, 11, 0), ServerType.MariaDb);
builder.Services.AddDbContext<AppDbContext>(opt => opt.UseMySql(cs, serverVersion));

builder.Services.AddCors(options =>
{
    options.AddPolicy("Dev", p => p
        .WithOrigins(cfg.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? Array.Empty<string>())
        .AllowAnyHeader()
        .AllowAnyMethod());
});

builder.Services.Scan(s => s
    .FromAssemblyOf<DeviceController>()
    .AddClasses(c => c.AssignableTo<IController>())
    .As<IController>()
    .WithSingletonLifetime());

builder.Services.AddControllers();

var app = builder.Build();

app.Logger.LogInformation("ContentRoot : {cr}", app.Environment.ContentRootPath);
app.Logger.LogInformation("WebRoot     : {wr}", app.Environment.WebRootPath);
app.Logger.LogInformation("index.html? : {ok}",
    File.Exists(Path.Combine(app.Environment.WebRootPath ?? "", "index.html")));
app.Logger.LogInformation("Listening   : http://localhost:{port}/", port);

app.MapGet("/ping", () => Results.Ok("pong"));

app.UseCors("Dev");

app.UseDefaultFiles();   // index.html, default.htm
app.UseStaticFiles();   

app.MapControllers();

app.MapFallbackToFile("index.html");

foreach (var mapper in app.Services.GetRequiredService<IEnumerable<IController>>())
    mapper.Map(app);

await app.RunAsync();
