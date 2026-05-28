using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UrduMeaning.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddApprovedWords : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                CREATE TABLE IF NOT EXISTS approved_words (
                    word text PRIMARY KEY,
                    source text NOT NULL DEFAULT 'manual',
                    priority integer NOT NULL DEFAULT 3,
                    created_at timestamp with time zone NOT NULL DEFAULT now()
                );
                """);

            migrationBuilder.Sql("""
                CREATE INDEX IF NOT EXISTS idx_approved_words_priority
                ON approved_words(priority);
                """);

            // Existing queue rows are already curated/processed vocabulary.
            // Do not backfill from word_definitions; live-generation pollution
            // would become permanently approved.
            migrationBuilder.Sql("""
                INSERT INTO approved_words (word, source, priority, created_at)
                SELECT lower(word), 'word_queue', min(priority), now()
                FROM word_queue
                GROUP BY lower(word)
                ON CONFLICT (word) DO UPDATE
                SET priority = LEAST(approved_words.priority, EXCLUDED.priority),
                    source = CASE
                        WHEN approved_words.source = 'manual' THEN approved_words.source
                        ELSE 'word_queue'
                    END;
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("DROP INDEX IF EXISTS idx_approved_words_priority;");
            migrationBuilder.Sql("DROP TABLE IF EXISTS approved_words;");
        }
    }
}
