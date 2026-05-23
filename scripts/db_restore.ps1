# =============================================================================
# scripts/db_restore.ps1
#
# Restores word_definitions from data/word_definitions_backup.sql into the
# running Postgres container.  Safe to run on a fresh DB or an existing one.
#
# Usage:
#   .\scripts\db_restore.ps1           # prompts before overwriting existing data
#   .\scripts\db_restore.ps1 -Force    # skips the prompt (use in automation)
#
# Requirements:
#   Docker running (docker compose up -d)
#   EF migrations already applied (dotnet ef database update)
# =============================================================================

param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$BackupFile = "data\word_definitions_backup.sql"

Write-Host ""
Write-Host "LughatAI — Database Restore" -ForegroundColor Cyan
Write-Host "===========================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Check backup file exists ───────────────────────────────────────────────
if (-not (Test-Path $BackupFile)) {
    Write-Host "Backup file not found: $BackupFile" -ForegroundColor Red
    Write-Host "Pull the latest from GitHub first:" -ForegroundColor Yellow
    Write-Host "  git pull" -ForegroundColor Yellow
    exit 1
}

$fileSize = [math]::Round((Get-Item $BackupFile).Length / 1KB, 1)
Write-Host "  Backup file: $BackupFile (${fileSize} KB)" -ForegroundColor Green

# ── 2. Check Docker is running ───────────────────────────────────────────────
Write-Host "Checking Docker..." -ForegroundColor Gray
$containerRunning = docker compose ps --status running --services 2>$null | Select-String "postgres"
if (-not $containerRunning) {
    Write-Host "Postgres container is not running. Start it first:" -ForegroundColor Red
    Write-Host "  docker compose up -d" -ForegroundColor Yellow
    exit 1
}
Write-Host "  Postgres container: OK" -ForegroundColor Green

# ── 3. Check existing data ────────────────────────────────────────────────────
$existing = (docker compose exec -T postgres psql -U postgres -d lughatai -t -c "SELECT COUNT(*) FROM word_definitions;" 2>$null) -join "" | ForEach-Object { $_.Trim() }
Write-Host "  Words currently in DB: $existing" -ForegroundColor Green
Write-Host ""

if ([int]$existing -gt 0) {
    if (-not $Force) {
        Write-Host "The database already has $existing words." -ForegroundColor Yellow
        Write-Host "Restoring will REPLACE all existing word_definitions." -ForegroundColor Yellow
        Write-Host ""
        $confirm = Read-Host "Type YES to continue"
        if ($confirm -ne "YES") {
            Write-Host "Aborted." -ForegroundColor Gray
            exit 0
        }
        Write-Host ""
    }

    # Truncate existing data and reset the ID sequence
    Write-Host "Clearing existing word_definitions..." -ForegroundColor Gray
    docker compose exec -T postgres psql -U postgres -d lughatai -c `
        "TRUNCATE TABLE word_definitions RESTART IDENTITY CASCADE;" | Out-Null
    Write-Host "  Cleared." -ForegroundColor Green
}

# ── 4. Run the restore ────────────────────────────────────────────────────────
Write-Host "Restoring from $BackupFile..." -ForegroundColor Gray

Get-Content $BackupFile -Encoding UTF8 -Raw | `
    docker compose exec -T postgres psql -U postgres -d lughatai -q

if ($LASTEXITCODE -ne 0) {
    Write-Host "Restore failed. Check the output above." -ForegroundColor Red
    exit 1
}

# ── 5. Verify ─────────────────────────────────────────────────────────────────
$restored = (docker compose exec -T postgres psql -U postgres -d lughatai -t -c "SELECT COUNT(*) FROM word_definitions;" 2>$null) -join "" | ForEach-Object { $_.Trim() }
Write-Host ""
Write-Host "Restore complete: $restored words in database." -ForegroundColor Green
Write-Host ""
