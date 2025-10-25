
namespace GreenKasse.App.Utils;

public static class PostApiDispatcher
{
    public static IServiceCollection AddApiControllers(this IServiceCollection services)
    {
        services.Scan(scan => scan
            .FromAssembliesOf(typeof(PostApiDispatcher)) 
            .AddClasses(c => c.AssignableTo<IController>())
            .AsImplementedInterfaces()
            .WithSingletonLifetime());

        return services;
    }

    public static IEndpointRouteBuilder MapAllApi(this IEndpointRouteBuilder app)
    {
        var controllers = app.ServiceProvider.GetServices<IController>();
        foreach (var c in controllers) c.Map(app);
        return app;
    }
}