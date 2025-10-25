using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace GreenKasse.Devices.Extensions

{
    public static class ServiceCollectionExtensions
    {
        public static IServiceCollection AddDevices(this IServiceCollection s, IConfiguration cfg)
        {
            s.AddSingleton<ICashDrawer, CashDrawerViaPrinter>();
            s.AddSingleton<EscPosBonPrinter>();
            s.AddSingleton<IBonPrinter, FallbackBonPrinter>(); 
            return s;
        }
    }
}