using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UrduMeaning.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddCorrectionDefinitionSnapshot : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                ALTER TABLE corrections
                    ADD COLUMN IF NOT EXISTS definition_snapshot jsonb,
                    ADD COLUMN IF NOT EXISTS definition_model varchar(100),
                    ADD COLUMN IF NOT EXISTS definition_updated_at timestamptz;
                """);

            migrationBuilder.Sql("""
                CREATE INDEX IF NOT EXISTS idx_corrections_status_created
                    ON corrections(status, created_at DESC);
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("DROP INDEX IF EXISTS idx_corrections_status_created;");
            migrationBuilder.Sql("""
                ALTER TABLE corrections
                    DROP COLUMN IF EXISTS definition_updated_at,
                    DROP COLUMN IF EXISTS definition_model,
                    DROP COLUMN IF EXISTS definition_snapshot;
                """);
        }
    }
}
