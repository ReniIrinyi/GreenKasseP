namespace GreenKasse.App.Adapter.Database;

using Microsoft.EntityFrameworkCore;

public sealed class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<KasseConfig> KasseConfigs => Set<KasseConfig>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.HasCharSet("utf8mb4").UseCollation("utf8mb4_unicode_ci");

        b.Entity<KasseConfig>(e =>
        {
            e.HasKey(x => x.Id);
            e.Property(x => x.Key).HasMaxLength(128).IsRequired();
            e.Property(x => x.Value).HasMaxLength(1024);
            e.HasIndex(x => x.Key).IsUnique();
        });
    }
}

public sealed class KasseConfig
{
    public long Id { get; set; }
    public string Key { get; set; } = null!;
    public string? Value { get; set; }
}