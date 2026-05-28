using Microsoft.EntityFrameworkCore;
using UrduMeaning.Api.Models;

namespace UrduMeaning.Api.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<WordDefinition> WordDefinitions { get; set; }
    public DbSet<ApprovedWord> ApprovedWords { get; set; }
    public DbSet<WordQueue> WordQueue { get; set; }
    public DbSet<User> Users { get; set; }
    public DbSet<UserFavorite> UserFavorites { get; set; }
    public DbSet<UserHistory> UserHistories { get; set; }
    public DbSet<Correction> Corrections { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<WordDefinition>(entity =>
        {
            entity.ToTable("word_definitions");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id").ValueGeneratedOnAdd();
            entity.Property(e => e.Word).HasColumnName("word").IsRequired();
            entity.Property(e => e.WordLower).HasColumnName("word_lower")
                  .HasComputedColumnSql("lower(word)", stored: true);
            entity.Property(e => e.Data).HasColumnName("data")
                  .HasColumnType("jsonb").IsRequired().HasDefaultValue("{}");
            entity.Property(e => e.LookupCount).HasColumnName("lookup_count").HasDefaultValue(0);
            entity.Property(e => e.CreatedAt).HasColumnName("created_at")
                  .HasDefaultValueSql("now()");
            entity.Property(e => e.UpdatedAt).HasColumnName("updated_at")
                  .HasDefaultValueSql("now()");
            entity.HasIndex(e => e.WordLower).HasDatabaseName("idx_word_lower");
            entity.HasIndex(e => e.LookupCount).HasDatabaseName("idx_lookup_count")
                  .IsDescending();
        });

        modelBuilder.Entity<ApprovedWord>(entity =>
        {
            entity.ToTable("approved_words");
            entity.HasKey(e => e.Word);
            entity.Property(e => e.Word).HasColumnName("word").IsRequired();
            entity.Property(e => e.Source).HasColumnName("source").IsRequired().HasDefaultValue("manual");
            entity.Property(e => e.Priority).HasColumnName("priority").HasDefaultValue(3);
            entity.Property(e => e.CreatedAt).HasColumnName("created_at")
                  .HasDefaultValueSql("now()");
            entity.HasIndex(e => e.Priority).HasDatabaseName("idx_approved_words_priority");
        });

        modelBuilder.Entity<WordQueue>(entity =>
        {
            entity.ToTable("word_queue");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id").ValueGeneratedOnAdd();
            entity.Property(e => e.Word).HasColumnName("word").IsRequired();
            entity.HasIndex(e => e.Word).IsUnique().HasDatabaseName("idx_word_queue_word");
            entity.Property(e => e.Status).HasColumnName("status").HasDefaultValue("pending");
            entity.Property(e => e.Priority).HasColumnName("priority").HasDefaultValue(3);
            entity.Property(e => e.Attempts).HasColumnName("attempts").HasDefaultValue(0);
            entity.Property(e => e.ErrorMessage).HasColumnName("error_message");
            entity.Property(e => e.CreatedAt).HasColumnName("created_at")
                  .HasDefaultValueSql("now()");
            entity.Property(e => e.UpdatedAt).HasColumnName("updated_at")
                  .HasDefaultValueSql("now()");
        });

        modelBuilder.Entity<User>(entity =>
        {
            entity.ToTable("users");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id").ValueGeneratedOnAdd();
            entity.Property(e => e.Username).HasColumnName("username").IsRequired();
            entity.Property(e => e.Email).HasColumnName("email").IsRequired();
            entity.HasIndex(e => e.Email).IsUnique().HasDatabaseName("idx_users_email");
            entity.HasIndex(e => e.Username).IsUnique().HasDatabaseName("idx_users_username");
            entity.Property(e => e.PasswordHash).HasColumnName("password_hash").IsRequired();
            entity.Property(e => e.Tier).HasColumnName("tier").HasDefaultValue("free");
            entity.Property(e => e.RefreshToken).HasColumnName("refresh_token");
            entity.Property(e => e.RefreshTokenExpiresAt).HasColumnName("refresh_token_expires_at");
            entity.Property(e => e.CreatedAt).HasColumnName("created_at")
                  .HasDefaultValueSql("now()");
            entity.Property(e => e.UpdatedAt).HasColumnName("updated_at")
                  .HasDefaultValueSql("now()");
        });

        modelBuilder.Entity<UserFavorite>(entity =>
        {
            entity.ToTable("user_favorites");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id").ValueGeneratedOnAdd();
            entity.Property(e => e.UserId).HasColumnName("user_id");
            entity.Property(e => e.Word).HasColumnName("word").IsRequired();
            entity.HasIndex(e => new { e.UserId, e.Word }).IsUnique()
                  .HasDatabaseName("idx_user_favorites_user_word");
            entity.Property(e => e.CreatedAt).HasColumnName("created_at")
                  .HasDefaultValueSql("now()");
        });

        modelBuilder.Entity<UserHistory>(entity =>
        {
            entity.ToTable("user_history");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id").ValueGeneratedOnAdd();
            entity.Property(e => e.UserId).HasColumnName("user_id");
            entity.Property(e => e.Word).HasColumnName("word").IsRequired();
            entity.HasIndex(e => new { e.UserId, e.LookedUpAt })
                  .HasDatabaseName("idx_user_history_user_time");
            entity.Property(e => e.LookedUpAt).HasColumnName("looked_up_at")
                  .HasDefaultValueSql("now()");
        });

        modelBuilder.Entity<Correction>(entity =>
        {
            entity.ToTable("corrections");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id").ValueGeneratedOnAdd();
            entity.Property(e => e.Word).HasColumnName("word").IsRequired();
            entity.Property(e => e.UserId).HasColumnName("user_id");
            entity.Property(e => e.Reason).HasColumnName("reason").HasDefaultValue("other");
            entity.Property(e => e.Notes).HasColumnName("notes");
            entity.Property(e => e.Status).HasColumnName("status").HasDefaultValue("open");
            entity.HasIndex(e => e.Word).HasDatabaseName("idx_corrections_word");
            entity.Property(e => e.CreatedAt).HasColumnName("created_at")
                  .HasDefaultValueSql("now()");
        });
    }
}
