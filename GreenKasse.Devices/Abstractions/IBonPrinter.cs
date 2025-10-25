
using GreenKasse.Devices.Dto; 

public interface IBonPrinter : IDevice
{
    PrintStatus Print(Bon bon);
}