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
# Always relative to repo root (parent of scripts/) regardless of where user runs from
$RepoRoot  = Split-Path $PSScriptRoot -Parent
$BackupFile = Join-Path $RepoRoot "data\word_definitions_backup.sql.gz"
Add-Type -AssemblyName "System.IO.Compression"

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

# Ensure data/ directory exists at repo root
$dataDir = Join-Path $RepoRoot "data"
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir | Out-Null }

# Stream dump from inside the container
Write-Host "  Running pg_dump..." -ForegroundColor Gray
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

# Compress with GZip — keeps file well under GitHub's 100 MB limit
$sqlBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($dumpContent -join "`n")
$fs = [System.IO.File]::Create($BackupFile)
$gz = [System.IO.Compression.GZipStream]::new($fs, [System.IO.Compression.CompressionLevel]::Optimal)
$gz.Write($sqlBytes, 0, $sqlBytes.Length)
$gz.Close(); $fs.Close()

$fileSizeMb = [math]::Round((Get-Item $BackupFile).Length / 1MB, 1)
Write-Host "  Saved: $BackupFile ($wordCount words, ${fileSizeMb} MB compressed)" -ForegroundColor Green
Write-Host ""

# ── 5. Print git commands ─────────────────────────────────────────────────────
$relPath = "data\word_definitions_backup.sql.gz"
Write-Host "Push to GitHub:" -ForegroundColor Cyan
Write-Host "  git add $relPath" -ForegroundColor White
Write-Host "  git commit -m `"backup: $wordCount words`"" -ForegroundColor White
Write-Host "  git push" -ForegroundColor White
Write-Host ""
