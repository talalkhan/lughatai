# =============================================================================
# scripts/db_backup.ps1
#
# Exports word_definitions to data/word_definitions_backup.sql and tells you
# the exact git commands to push it to GitHub.
#
# Usage:
#   .\scripts\db_backup.ps1
#
# Requirements:
#   Docker running (docker compose up -d)
# =============================================================================

$ErrorActionPreference = "Stop"
$BackupFile = "data\word_definitions_backup.sql"

Write-Host ""
Write-Host "LughatAI — Database Backup" -ForegroundColor Cyan
Write-Host "==========================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Check Docker is running ───────────────────────────────────────────────
Write-Host "Checking Docker..." -ForegroundColor Gray
$containerRunning = docker compose ps --status running --services 2>$null | Select-String "postgres"
if (-not $containerRunning) {
    Write-Host "Postgres container is not running. Start it first:" -ForegroundColor Red
    Write-Host "  docker compose up -d" -ForegroundColor Yellow
    exit 1
}
Write-Host "  Postgres container: OK" -ForegroundColor Green

# ── 2. Count words before backup ─────────────────────────────────────────────
$wordCount = (docker compose exec -T postgres psql -U postgres -d lughatai -t -c "SELECT COUNT(*) FROM word_definitions;" 2>$null) -join "" | ForEach-Object { $_.Trim() }
Write-Host "  Words in database: $wordCount" -ForegroundColor Green
Write-Host ""

if ([int]$wordCount -eq 0) {
    Write-Host "Database is empty — nothing to back up." -ForegroundColor Yellow
    exit 0
}

# ── 3. Run pg_dump ───────────────────────────────────────────────────────────
Write-Host "Running pg_dump..." -ForegroundColor Gray

# Ensure data/ directory exists
if (-not (Test-Path "data")) { New-Item -ItemType Directory -Path "data" | Out-Null }

# Stream dump from inside the container, write as UTF-8 (required for Urdu text)
$dumpContent = docker compose exec -T postgres pg_dump `
    -U postgres `
    -d lughatai `
    --data-only `
    --table=word_definitions `
    --no-acl `
    --no-owner 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "pg_dump failed:" -ForegroundColor Red
    Write-Host $dumpContent -ForegroundColor Red
    exit 1
}

# Write UTF-8 without BOM (important: Urdu Unicode must survive the round-trip)
[System.IO.File]::WriteAllText(
    (Join-Path (Get-Location) $BackupFile),
    ($dumpContent -join "`n"),
    [System.Text.UTF8Encoding]::new($false)  # $false = no BOM
)

$fileSize = [math]::Round((Get-Item $BackupFile).Length / 1KB, 1)
Write-Host "  Saved: $BackupFile ($wordCount words, ${fileSize} KB)" -ForegroundColor Green
Write-Host ""

# ── 4. Warn if file is getting large ─────────────────────────────────────────
if ($fileSize -gt 80000) {
    Write-Host "WARNING: Backup file is >80 MB. GitHub has a 100 MB hard limit." -ForegroundColor Yellow
    Write-Host "Consider using Git LFS: https://git-lfs.github.com" -ForegroundColor Yellow
    Write-Host ""
}

# ── 5. Print git commands ─────────────────────────────────────────────────────
Write-Host "Push to GitHub:" -ForegroundColor Cyan
Write-Host "  git add $BackupFile" -ForegroundColor White
Write-Host "  git commit -m `"backup: $wordCount words`"" -ForegroundColor White
Write-Host "  git push" -ForegroundColor White
Write-Host ""
