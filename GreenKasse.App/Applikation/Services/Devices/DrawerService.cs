
public class DrawerService
{
    private readonly ICashDrawer _drawer;
    public DrawerService(ICashDrawer drawer) => _drawer = drawer;

    public Task OpenAsync(CancellationToken ct)
    {
        _drawer.Open();
        return Task.CompletedTask;
    }
}