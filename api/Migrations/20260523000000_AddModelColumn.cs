using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UrduMeaning.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddModelColumn : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Dedicated column for the AI model that generated the word data.
            // Faster to query/filter than the equivalent data->'_meta'->>'model' JSON path.
            migrationBuilder.Sql(
                "ALTER TABLE word_definitions ADD COLUMN IF NOT EXISTS model varchar(100);");

            // Backfill existing rows from the _meta.model field already in the JSONB
            migrationBuilder.Sql(
                "UPDATE word_definitions SET model = data->'_meta'->>'model' WHERE model IS NULL;");

            // Index for provider-breakdown queries and admin dashboards
            migrationBuilder.Sql(
                "CREATE INDEX IF NOT EXISTS idx_word_definitions_model ON word_definitions(model);");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("DROP INDEX IF EXISTS idx_word_definitions_model;");
            migrationBuilder.Sql("ALTER TABLE word_definitions DROP COLUMN IF EXISTS model;");
        }
    }
}
