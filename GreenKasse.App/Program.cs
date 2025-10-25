using GreenKasse.App.Adapter.Database;
using GreenKasse.App.Applikation.Services;
using GreenKasse.Devices.Extensions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.FileProviders;
using Pomelo.EntityFrameworkCore.MySql.Infrastructure;

var builder = WebApplication.CreateBuilder(args);
var projectRoot = builder.Environment.ContentRootPath;
var solutionRoot = Directory.GetParent(projectRoot)!.FullName;


builder.Configuration
    .AddJsonFile(Path.Combine(solutionRoot, "appsettings.json"), optional: false, reloadOnChange: true)
    .AddJsonFile(Path.Combine(solutionRoot, $"appsettings.{builder.Environment.EnvironmentName}.json"), optional: true, reloadOnChange: true)
    .AddEnvironmentVariables();

var cfg = builder.Configuration;
builder.Services.AddDevices(builder.Configuration);
builder.Services.AddScoped<DrawerService>();
var cs = builder.Configuration.GetConnectionString("MariaDb")!;
var serverVersion = ServerVersion.Create(new Version(10, 11, 0), ServerType.MariaDb);
builder.Services.AddDbContext<AppDbContext>(opt =>
{
    opt.UseMySql(cs, serverVersion);
});


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
app.UseCors("Dev");
app.MapFallbackToFile("index.html");
app.UseDefaultFiles();
app.UseStaticFiles();
app.MapControllers();
var routeMappers = app.Services.GetRequiredService<IEnumerable<IController>>();
foreach (var mapper in routeMappers)
{
    mapper.Map(app);
}
await app.RunAsync();