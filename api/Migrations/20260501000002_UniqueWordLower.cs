using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UrduMeaning.Api.Migrations
{
    /// <inheritdoc />
    public partial class UniqueWordLower : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Replace the non-unique idx_word_lower with a unique one so
            // INSERT ... ON CONFLICT (word_lower) DO UPDATE works correctly.
            migrationBuilder.Sql("DROP INDEX IF EXISTS idx_word_lower;");
            migrationBuilder.Sql("CREATE UNIQUE INDEX idx_word_lower ON word_definitions(word_lower);");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("DROP INDEX IF EXISTS idx_word_lower;");
            migrationBuilder.Sql("CREATE INDEX idx_word_lower ON word_definitions(word_lower);");
        }
    }
}
