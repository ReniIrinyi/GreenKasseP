using System.Net;
using GreenKasse.Infrastructure.System;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace GreenKasse.Infrastructure.Extensions;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection s, IConfiguration cfg)
    {
        s.AddSingleton<DeviceIdProvider>();
        s.AddSingleton<ICredentialService, CredentialService>();
        s.AddHttpClient<ICloudAuthClient, CloudAuthClient>(client =>
        {
            client.BaseAddress = new Uri(cfg["Cloud:BaseUrl"]!);
        })
        .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler
        {
            CookieContainer = new CookieContainer(),
            UseCookies = true,
            AllowAutoRedirect = false
        });

        return s;
    }
}

