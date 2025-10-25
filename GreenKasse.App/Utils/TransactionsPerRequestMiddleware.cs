using GreenKasse.App.Adapter.Database;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;

namespace GreenKasse.App.Utils;

public sealed class TransactionsPerRequestMiddleware
{
    private readonly RequestDelegate _next;

    public TransactionsPerRequestMiddleware(RequestDelegate next) => _next = next;

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

            if (ctx.Response.StatusCode < 400)
            {
                await db.SaveChangesAsync(ctx.RequestAborted);
                await tx.CommitAsync(ctx.RequestAborted);
            }
            else
            {
                await tx.RollbackAsync(ctx.RequestAborted);
            }
        }
        catch
        {
            await tx.RollbackAsync(ctx.RequestAborted);
            throw;
        }
    }
}