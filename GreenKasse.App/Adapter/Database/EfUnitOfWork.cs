using Microsoft.EntityFrameworkCore;        
using Microsoft.EntityFrameworkCore.Storage;

namespace GreenKasse.App.Adapter.Database;

public sealed class EfUnitOfWork<TDbContext> : IUnitOfWork
    where TDbContext : DbContext
{
    private readonly TDbContext _db;
    private IDbContextTransaction? _tx;

    public EfUnitOfWork(TDbContext db) => _db = db;

    public async Task BeginAsync(CancellationToken ct)
        => _tx = await _db.Database.BeginTransactionAsync(ct);

    public async Task CommitAsync(CancellationToken ct)
    {
        await _db.SaveChangesAsync(ct);
        if (_tx is not null)
            await _tx.CommitAsync(ct);
    }

    public async Task RollbackAsync(CancellationToken ct)
    {
        if (_tx is not null)
            await _tx.RollbackAsync(ct);
    }

    public async ValueTask DisposeAsync()
    {
        if (_tx is not null)
            await _tx.DisposeAsync();
    }
}