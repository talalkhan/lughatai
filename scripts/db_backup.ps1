# =============================================================================
# scripts/db_backup.ps1
#
# Streams word_definitions to compressed SQL backup parts under data/.
# Parts are capped below GitHub's 100 MB limit so the backup can keep growing.
#
# Usage:
#   .\scripts\db_backup.ps1
#
# Requirements:
#   Docker running (docker compose up -d)
# =============================================================================

param(
    [int]$MaxPartSizeMb = 85
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$DataDir = Join-Path $RepoRoot "data"
$BackupStem = "word_definitions_backup"
$LegacyBackupFile = Join-Path $DataDir "$BackupStem.sql.gz"
Add-Type -AssemblyName "System.IO.Compression"

function New-DockerProcess([string]$arguments) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "docker"
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    return [System.Diagnostics.Process]::Start($psi)
}

function Open-BackupPart([string]$directory, [string]$stem, [int]$index) {
    $path = Join-Path $directory ("{0}.part{1:D3}.sql.gz" -f $stem, $index)
    $fileStream = [System.IO.File]::Create($path)
    $gzipStream = [System.IO.Compression.GZipStream]::new($fileStream, [System.IO.Compression.CompressionLevel]::Optimal)
    $writer = [System.IO.StreamWriter]::new($gzipStream, [System.Text.UTF8Encoding]::new($false))
    return [PSCustomObject]@{
        Path = $path
        FileStream = $fileStream
        GZipStream = $gzipStream
        Writer = $writer
    }
}

function Close-BackupPart($part) {
    if ($null -eq $part) { return }
    try { $part.Writer.Flush() } catch {}
    try { $part.Writer.Dispose() } catch {}
}

Write-Host ""
Write-Host "LughatAI — Database Backup" -ForegroundColor Cyan
Write-Host "==========================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Checking Docker..." -ForegroundColor Gray
$containerRunning = docker compose ps --status running --services 2>$null | Select-String "postgres"
if (-not $containerRunning) {
    Write-Host "Postgres container is not running. Start it first:" -ForegroundColor Red
    Write-Host "  docker compose up -d" -ForegroundColor Yellow
    exit 1
}
Write-Host "  Postgres container: OK" -ForegroundColor Green

$wordCount = (docker compose exec -T postgres psql -U postgres -d lughatai -t -c "SELECT COUNT(*) FROM word_definitions;" 2>$null) -join "" | ForEach-Object { $_.Trim() }
Write-Host "  Words in database: $wordCount" -ForegroundColor Green
Write-Host ""

if ([int]$wordCount -eq 0) {
    Write-Host "Database is empty — nothing to back up." -ForegroundColor Yellow
    exit 0
}

if (-not (Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir | Out-Null
}

Get-ChildItem -Path $DataDir -Filter "$BackupStem*.sql.gz" -ErrorAction SilentlyContinue | Remove-Item -Force

Write-Host "Running pg_dump..." -ForegroundColor Gray
$dumpArgs = "compose exec -T postgres pg_dump -U postgres -d lughatai --data-only --table=word_definitions --no-acl --no-owner"
$process = New-DockerProcess $dumpArgs

$maxPartBytes = $MaxPartSizeMb * 1MB
$partIndex = 1
$part = Open-BackupPart -directory $DataDir -stem $BackupStem -index $partIndex
$parts = New-Object System.Collections.Generic.List[object]
$lineCounter = 0

while (($line = $process.StandardOutput.ReadLine()) -ne $null) {
    $part.Writer.WriteLine($line)
    $lineCounter++

    if (($lineCounter % 250) -eq 0) {
        $part.Writer.Flush()
        if ((Get-Item $part.Path).Length -ge $maxPartBytes -and $process.StandardOutput.Peek() -ge 0) {
            Close-BackupPart $part
            $parts.Add([PSCustomObject]@{
                Path = $part.Path
                SizeBytes = (Get-Item $part.Path).Length
            })
            $partIndex++
            $part = Open-BackupPart -directory $DataDir -stem $BackupStem -index $partIndex
            Write-Host ("  Rotated backup -> {0}" -f [System.IO.Path]::GetFileName($part.Path)) -ForegroundColor DarkGray
        }
    }
}

Close-BackupPart $part
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()

if ($process.ExitCode -ne 0) {
    Write-Host "pg_dump failed:" -ForegroundColor Red
    Write-Host $stderr -ForegroundColor Red
    exit 1
}

$parts.Add([PSCustomObject]@{
    Path = $part.Path
    SizeBytes = (Get-Item $part.Path).Length
})

$totalCompressedBytes = ($parts | Measure-Object -Property SizeBytes -Sum).Sum
$totalCompressedMb = [math]::Round($totalCompressedBytes / 1MB, 1)

Write-Host "  Saved $($parts.Count) backup part(s):" -ForegroundColor Green
foreach ($entry in $parts) {
    $sizeMb = [math]::Round($entry.SizeBytes / 1MB, 1)
    Write-Host ("    {0} ({1} MB)" -f [System.IO.Path]::GetFileName($entry.Path), $sizeMb) -ForegroundColor Gray
}
Write-Host "  Total compressed size: $totalCompressedMb MB" -ForegroundColor Green
Write-Host ""

Write-Host "Push to GitHub:" -ForegroundColor Cyan
Write-Host "  git add data\$BackupStem*.sql.gz" -ForegroundColor White
Write-Host "  git commit -m `"backup: $wordCount words`"" -ForegroundColor White
Write-Host "  git push" -ForegroundColor White
Write-Host ""
