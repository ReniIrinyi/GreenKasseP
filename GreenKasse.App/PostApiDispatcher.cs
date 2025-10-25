using System.Reflection;
using GreenKasse.App.Adapter.Controller;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;


public static class PostApiDispatcher
{
    public static IServiceCollection AddApiControllers(this IServiceCollection services)
    {
        var asm = typeof(PostApiDispatcher).Assembly;

        var controllers = asm
            .GetTypes()
            .Where(t => typeof(IController).IsAssignableFrom(t)
                        && t.IsClass && !t.IsAbstract && t.GetConstructor(Type.EmptyTypes) != null);

        foreach (var t in controllers)
            services.AddSingleton(typeof(IController), t);

        return services;
    }

    public static IEndpointRouteBuilder MapAllApi(this IEndpointRouteBuilder app)
    {
        var controllers = app.ServiceProvider.GetServices<IController>();
        foreach (var c in controllers) c.Map(app);
        return app;
    }
}