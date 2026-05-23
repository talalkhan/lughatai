using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace LughatAI.Api.Migrations
{
    /// <inheritdoc />
    public partial class InitialSchema : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "word_definitions",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    word = table.Column<string>(type: "text", nullable: false),
                    word_lower = table.Column<string>(type: "text", nullable: false, computedColumnSql: "lower(word)", stored: true),
                    data = table.Column<string>(type: "jsonb", nullable: false, defaultValue: "{}"),
                    lookup_count = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_word_definitions", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "word_queue",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    word = table.Column<string>(type: "text", nullable: false),
                    status = table.Column<string>(type: "text", nullable: false, defaultValue: "pending"),
                    priority = table.Column<int>(type: "integer", nullable: false, defaultValue: 3),
                    attempts = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    error_message = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_word_queue", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "idx_lookup_count",
                table: "word_definitions",
                column: "lookup_count",
                descending: new bool[0]);

            migrationBuilder.CreateIndex(
                name: "idx_word_lower",
                table: "word_definitions",
                column: "word_lower");

            migrationBuilder.CreateIndex(
                name: "idx_word_queue_word",
                table: "word_queue",
                column: "word",
                unique: true);

            // GIN index on JSONB data column for fast JSONB queries
            migrationBuilder.Sql("CREATE INDEX idx_data_gin ON word_definitions USING GIN(data);");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("DROP INDEX IF EXISTS idx_data_gin;");

            migrationBuilder.DropTable(
                name: "word_definitions");

            migrationBuilder.DropTable(
                name: "word_queue");
        }
    }
}
