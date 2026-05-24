# =============================================================================
# scripts/db_restore.ps1
#
# Restores word_definitions from sharded or legacy compressed SQL backups.
# Safe to run on a fresh DB or an existing one.
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
$RepoRoot = Split-Path $PSScriptRoot -Parent
$DataDir = Join-Path $RepoRoot "data"
$BackupStem = "word_definitions_backup"
$LegacyBackupFile = Join-Path $DataDir "$BackupStem.sql.gz"
Add-Type -AssemblyName "System.IO.Compression"

function Resolve-BackupFiles {
    $parts = Get-ChildItem -Path $DataDir -Filter "$BackupStem.part*.sql.gz" -ErrorAction SilentlyContinue |
        Sort-Object Name
    if ($parts.Count -gt 0) {
        return ,$parts
    }

    if (Test-Path $LegacyBackupFile) {
        return ,(Get-Item $LegacyBackupFile)
    }

    return @()
}

function New-DockerPsqlProcess {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "docker"
    $psi.Arguments = "compose exec -T postgres psql -U postgres -d lughatai -q"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    return [System.Diagnostics.Process]::Start($psi)
}

Write-Host ""
Write-Host "UrduMeaning — Database Restore" -ForegroundColor Cyan
Write-Host "===========================" -ForegroundColor Cyan
Write-Host ""

$backupFiles = Resolve-BackupFiles
if ($backupFiles.Count -eq 0) {
    Write-Host "Backup file not found under $DataDir" -ForegroundColor Red
    Write-Host "Pull the latest from GitHub first:" -ForegroundColor Yellow
    Write-Host "  git pull" -ForegroundColor Yellow
    exit 1
}

$totalSizeKb = [math]::Round((($backupFiles | Measure-Object Length -Sum).Sum) / 1KB, 1)
Write-Host "  Backup part(s): $($backupFiles.Count) (${totalSizeKb} KB compressed)" -ForegroundColor Green
foreach ($file in $backupFiles) {
    Write-Host ("    {0}" -f $file.Name) -ForegroundColor Gray
}

Write-Host "Checking Docker..." -ForegroundColor Gray
$containerRunning = docker compose ps --status running --services 2>$null | Select-String "postgres"
if (-not $containerRunning) {
    Write-Host "Postgres container is not running. Start it first:" -ForegroundColor Red
    Write-Host "  docker compose up -d" -ForegroundColor Yellow
    exit 1
}
Write-Host "  Postgres container: OK" -ForegroundColor Green

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

    Write-Host "Clearing existing word_definitions..." -ForegroundColor Gray
    docker compose exec -T postgres psql -U postgres -d lughatai -c `
        "TRUNCATE TABLE word_definitions RESTART IDENTITY CASCADE;" | Out-Null
    Write-Host "  Cleared." -ForegroundColor Green
}

Write-Host "Restoring compressed SQL stream..." -ForegroundColor Gray
$psql = New-DockerPsqlProcess
$stdin = $psql.StandardInput
$buffer = New-Object char[] 16384

foreach ($file in $backupFiles) {
    Write-Host ("  Replaying {0}..." -f $file.Name) -ForegroundColor Gray
    $fileStream = [System.IO.File]::OpenRead($file.FullName)
    $gzipStream = [System.IO.Compression.GZipStream]::new($fileStream, [System.IO.Compression.CompressionMode]::Decompress)
    $reader = [System.IO.StreamReader]::new($gzipStream, [System.Text.Encoding]::UTF8)
    try {
        while (($read = $reader.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $stdin.Write($buffer, 0, $read)
        }
    } finally {
        $reader.Dispose()
    }
}

$stdin.Close()
$stdout = $psql.StandardOutput.ReadToEnd()
$stderr = $psql.StandardError.ReadToEnd()
$psql.WaitForExit()

if ($psql.ExitCode -ne 0) {
    Write-Host "Restore failed." -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        Write-Host $stderr -ForegroundColor Red
    }
    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        Write-Host $stdout -ForegroundColor DarkRed
    }
    exit 1
}

$restored = (docker compose exec -T postgres psql -U postgres -d lughatai -t -c "SELECT COUNT(*) FROM word_definitions;" 2>$null) -join "" | ForEach-Object { $_.Trim() }
Write-Host ""
Write-Host "Restore complete: $restored words in database." -ForegroundColor Green
Write-Host ""
