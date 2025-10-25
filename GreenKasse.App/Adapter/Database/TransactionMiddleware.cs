using GreenKasse.App.Adapter.Database;

public sealed class TransactionsPerRequestMiddleware
{
    private readonly RequestDelegate _next;

    public TransactionsPerRequestMiddleware(RequestDelegate next)
        => _next = next;

    public async Task InvokeAsync(HttpContext ctx, AppDbContext db)
    {
        if (!ctx.Request.Path.StartsWithSegments("/api"))
        {
            await _next(ctx);
            return;
        }

        await using var tx = await db.Database.BeginTransactionAsync(ctx.RequestAborted);
        try
        {
            await _next(ctx);
            await db.SaveChangesAsync(ctx.RequestAborted);
            await tx.CommitAsync(ctx.RequestAborted);
        }
        catch
        {
            await tx.RollbackAsync(ctx.RequestAborted);
            throw;
        }
    }
}