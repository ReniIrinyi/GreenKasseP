namespace GreenKasse.App.Adapter.Database;

public interface IUnitOfWork : IAsyncDisposable
{
    Task BeginAsync(CancellationToken ct);
    Task CommitAsync(CancellationToken ct);
    Task RollbackAsync(CancellationToken ct);
}
