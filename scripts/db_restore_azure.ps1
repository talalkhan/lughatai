# =============================================================================
# scripts/db_restore_azure.ps1
#
# Restores word_definitions from local backup files to Azure PostgreSQL.
# Decompresses backup parts into a temp file, copies into the Docker postgres
# container, then runs psql -f (avoids unreliable stdin piping for large dumps).
#
# Usage:
#   .\scripts\db_restore_azure.ps1
#   .\scripts\db_restore_azure.ps1 -Force   # skip confirmation prompt
#
# Requirements:
#   Docker running (docker compose up -d)
#   Backup files present in data/ (run .\scripts\db_backup.ps1 first)
#   Azure PostgreSQL firewall open for your IP
# =============================================================================

param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$RepoRoot   = Split-Path $PSScriptRoot -Parent
$DataDir    = Join-Path $RepoRoot "data"
$BackupStem = "word_definitions_backup"

$AzureHost = "lughatai-beta-db.postgres.database.azure.com"
$AzureDb   = "lughatai"
$AzureUser = "lughatadmin"
$AzurePass = 'NlehvAZp8NqwNvjh%755'
$ConnStr   = "host=$AzureHost port=5432 dbname=$AzureDb user=$AzureUser password=$AzurePass sslmode=require"

Add-Type -AssemblyName "System.IO.Compression"

Write-Host ""
Write-Host "UrduMeaning — Restore to Azure PostgreSQL" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# ── Find backup files ─────────────────────────────────────────────────────────
$backupFiles = Get-ChildItem -Path $DataDir -Filter "$BackupStem.part*.sql.gz" `
    -ErrorAction SilentlyContinue | Sort-Object Name

if ($backupFiles.Count -eq 0) {
    $legacy = Join-Path $DataDir "$BackupStem.sql.gz"
    if (Test-Path $legacy) { $backupFiles = @(Get-Item $legacy) }
}

if ($backupFiles.Count -eq 0) {
    Write-Host "No backup files found in $DataDir" -ForegroundColor Red
    Write-Host "Run .\scripts\db_backup.ps1 first." -ForegroundColor Yellow
    exit 1
}

$totalMb = [math]::Round((($backupFiles | Measure-Object Length -Sum).Sum) / 1MB, 1)
Write-Host "  Backup part(s): $($backupFiles.Count) ($totalMb MB compressed)" -ForegroundColor Green
foreach ($f in $backupFiles) { Write-Host "    $($f.Name)" -ForegroundColor Gray }
Write-Host ""

# ── Check Docker ──────────────────────────────────────────────────────────────
Write-Host "Checking Docker..." -ForegroundColor Gray
$running = docker compose ps --status running --services 2>$null | Select-String "postgres"
if (-not $running) {
    Write-Host "Postgres container not running. Run: docker compose up -d" -ForegroundColor Red
    exit 1
}
$containerId = (docker compose ps -q postgres 2>$null | Select-Object -First 1).Trim()
if (-not $containerId) {
    Write-Host "Could not get postgres container ID." -ForegroundColor Red
    exit 1
}
Write-Host "  Container: $containerId" -ForegroundColor Green

# ── Current word count on Azure ───────────────────────────────────────────────
Write-Host "Connecting to Azure PostgreSQL..." -ForegroundColor Gray
$existing = docker compose exec -T postgres psql "$ConnStr" -t -c "SELECT COUNT(*) FROM word_definitions;" 2>$null
$existing = ($existing -join "").Trim()
Write-Host "  Words currently on Azure: $existing" -ForegroundColor Green
Write-Host ""

# ── Confirm ───────────────────────────────────────────────────────────────────
if ([int]$existing -gt 0 -and -not $Force) {
    Write-Host "Azure already has $existing words. Restoring will REPLACE them all." -ForegroundColor Yellow
    $confirm = Read-Host "Type YES to continue"
    if ($confirm -ne "YES") { Write-Host "Aborted." -ForegroundColor Gray; exit 0 }
    Write-Host ""
}

# ── Decompress all parts into one temp SQL file ───────────────────────────────
$tempSql = Join-Path $env:TEMP "lughatai_restore_$(Get-Date -Format 'yyyyMMddHHmmss').sql"
Write-Host "Decompressing backup to temp file..." -ForegroundColor Gray

$outStream = [System.IO.File]::Create($tempSql)
try {
    foreach ($file in $backupFiles) {
        Write-Host "  Decompressing $($file.Name)..." -ForegroundColor Gray
        $fsIn = [System.IO.File]::OpenRead($file.FullName)
        $gz   = [System.IO.Compression.GZipStream]::new($fsIn, [System.IO.Compression.CompressionMode]::Decompress)
        try { $gz.CopyTo($outStream) }
        finally { $gz.Dispose(); $fsIn.Dispose() }
    }
} finally {
    $outStream.Dispose()
}

$decompMb = [math]::Round((Get-Item $tempSql).Length / 1MB, 1)
Write-Host "  Decompressed: $decompMb MB" -ForegroundColor Green

# ── Copy temp file into Docker container ──────────────────────────────────────
Write-Host "Copying SQL file into Docker container..." -ForegroundColor Gray
docker cp $tempSql "${containerId}:/tmp/lughatai_restore.sql" | Out-Null
Write-Host "  Copied." -ForegroundColor Green

# ── Clear existing data ───────────────────────────────────────────────────────
if ([int]$existing -gt 0) {
    Write-Host "Clearing existing word_definitions on Azure..." -ForegroundColor Gray
    docker compose exec -T postgres psql "$ConnStr" -c `
        "TRUNCATE TABLE word_definitions RESTART IDENTITY CASCADE;" | Out-Null
    Write-Host "  Cleared." -ForegroundColor Green
}

# ── Restore via psql -f ───────────────────────────────────────────────────────
Write-Host "Restoring to Azure (this may take a few minutes)..." -ForegroundColor Gray
$result = docker compose exec -T postgres psql "$ConnStr" `
    -v ON_ERROR_STOP=1 `
    -f /tmp/lughatai_restore.sql 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "Restore failed:" -ForegroundColor Red
    Write-Host $result -ForegroundColor Red
    exit 1
}

# ── Cleanup ───────────────────────────────────────────────────────────────────
docker compose exec -T postgres rm /tmp/lughatai_restore.sql | Out-Null
Remove-Item $tempSql -ErrorAction SilentlyContinue

# ── Final count ───────────────────────────────────────────────────────────────
$restored = docker compose exec -T postgres psql "$ConnStr" -t `
    -c "SELECT COUNT(*) FROM word_definitions;" 2>$null
$restored = ($restored -join "").Trim()

Write-Host ""
Write-Host "Restore complete: $restored words now on Azure." -ForegroundColor Green
Write-Host ""
