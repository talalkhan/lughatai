# =============================================================================
# scripts/db_restore_from_blob.ps1
#
# Lists available backups in Azure Blob Storage and restores a chosen one
# to Azure PostgreSQL. Defaults to the most recent backup.
#
# Usage:
#   .\scripts\db_restore_from_blob.ps1               # restore latest
#   .\scripts\db_restore_from_blob.ps1 -Date 2026-05-18  # restore specific date
#   .\scripts\db_restore_from_blob.ps1 -Force         # skip confirmation
#
# Requirements:
#   Azure CLI logged in (az login)
#   Docker running (docker compose up -d)  — used as psql client
# =============================================================================

param(
    [string]$Date  = "",   # e.g. "2026-05-18"; defaults to latest
    [string]$AzureConnStr = $env:LUGHATAI_AZURE_PG_CONN,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$StorageAccount = "lughataibetastorage"
$Container      = "db-backups"

if ([string]::IsNullOrWhiteSpace($AzureConnStr)) {
    Write-Host "Azure connection string is required." -ForegroundColor Red
    Write-Host "Pass -AzureConnStr or set LUGHATAI_AZURE_PG_CONN in your shell." -ForegroundColor Yellow
    exit 1
}

function Convert-ToPsqlConnStr([string]$connStr) {
    if ($connStr -notmatch ";") { return $connStr }
    $parts = @{}
    $connStr -split ";" | ForEach-Object {
        if ($_ -match "^(.*?)=(.*)$") {
            $parts[$matches[1].Trim().ToLowerInvariant()] = $matches[2].Trim()
        }
    }
    $hostName = $parts["host"]
    $port     = if ($parts.ContainsKey("port")) { $parts["port"] } else { "5432" }
    $dbName   = if ($parts.ContainsKey("database")) { $parts["database"] } else { $parts["dbname"] }
    $userName = if ($parts.ContainsKey("username")) { $parts["username"] } else { $parts["user id"] }
    $password = $parts["password"]
    if ([string]::IsNullOrWhiteSpace($hostName) -or [string]::IsNullOrWhiteSpace($dbName) -or [string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($password)) { return $connStr }
    return "host=$hostName port=$port dbname=$dbName user=$userName password=$password sslmode=require"
}

$AzureConnStr = Convert-ToPsqlConnStr $AzureConnStr
$ConnStr = $AzureConnStr

Add-Type -AssemblyName "System.IO.Compression"

Write-Host ""
Write-Host "UrduMeaning — Restore from Azure Blob Storage" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

# ── List available backups ────────────────────────────────────────────────────
Write-Host "Fetching available backups..." -ForegroundColor Gray
$blobs = az storage blob list `
    --account-name $StorageAccount `
    --container-name $Container `
    --auth-mode login `
    --query "sort_by([].{name:name, size:properties.contentLength, modified:properties.lastModified}, &name)" `
    --output json 2>$null | ConvertFrom-Json

if (-not $blobs -or $blobs.Count -eq 0) {
    Write-Host "No backups found in Azure Blob Storage." -ForegroundColor Red
    Write-Host "Run the backup workflow first or wait for Sunday's scheduled run." -ForegroundColor Yellow
    exit 1
}

Write-Host "  Available backups:" -ForegroundColor Green
foreach ($b in $blobs) {
    $sizeMb = [math]::Round($b.size / 1MB, 1)
    Write-Host ("    {0}  ({1} MB)  {2}" -f $b.name, $sizeMb, $b.modified) -ForegroundColor Gray
}
Write-Host ""

# ── Select blob ───────────────────────────────────────────────────────────────
if ($Date) {
    $blobName = "word_definitions_${Date}.sql.gz"
    $selected = $blobs | Where-Object { $_.name -eq $blobName }
    if (-not $selected) {
        Write-Host "No backup found for date: $Date" -ForegroundColor Red
        exit 1
    }
} else {
    $selected = $blobs | Select-Object -Last 1
    Write-Host "Using latest backup: $($selected.name)" -ForegroundColor Green
}

$blobName = $selected.name
$sizeMb   = [math]::Round($selected.size / 1MB, 1)
Write-Host "  Blob: $blobName ($sizeMb MB)" -ForegroundColor Green
Write-Host ""

# ── Check Docker ──────────────────────────────────────────────────────────────
Write-Host "Checking Docker..." -ForegroundColor Gray
$running = docker compose ps --status running --services 2>$null | Select-String "postgres"
if (-not $running) {
    Write-Host "Postgres container not running. Run: docker compose up -d" -ForegroundColor Red
    exit 1
}
$containerId = (docker compose ps -q postgres 2>$null | Select-Object -First 1).Trim()
Write-Host "  Container: $containerId" -ForegroundColor Green

# ── Open firewall ─────────────────────────────────────────────────────────────
Write-Host "Opening Azure PostgreSQL firewall for your IP..." -ForegroundColor Gray
$myIp = (Invoke-RestMethod -Uri "https://ifconfig.me/ip").Trim()
az postgres flexible-server firewall-rule create `
    --resource-group lughatai-beta-rg `
    --name lughatai-beta-db `
    --rule-name AllowLocalRestore `
    --start-ip-address $myIp `
    --end-ip-address $myIp `
    --output none 2>$null | Out-Null
Write-Host "  Opened for $myIp" -ForegroundColor Green

# ── Current word count ────────────────────────────────────────────────────────
$existing = (docker compose exec -T postgres psql "$ConnStr" -t `
    -c "SELECT COUNT(*) FROM word_definitions;" 2>$null) -join "" | ForEach-Object { $_.Trim() }
Write-Host ""
Write-Host "  Words currently on Azure: $existing" -ForegroundColor Green

# ── Confirm ───────────────────────────────────────────────────────────────────
if (-not $Force) {
    Write-Host ""
    Write-Host "This will REPLACE all $existing words with the backup from $blobName." -ForegroundColor Yellow
    $confirm = Read-Host "Type YES to continue"
    if ($confirm -ne "YES") {
        Write-Host "Aborted." -ForegroundColor Gray
        az postgres flexible-server firewall-rule delete `
            --resource-group lughatai-beta-rg `
            --name lughatai-beta-db `
            --rule-name AllowLocalRestore --yes --output none 2>$null | Out-Null
        exit 0
    }
}

# ── Download from Blob Storage ────────────────────────────────────────────────
$tempGz  = Join-Path $env:TEMP "lughatai_blob_restore.sql.gz"
$tempSql = Join-Path $env:TEMP "lughatai_blob_restore.sql"

Write-Host ""
Write-Host "Downloading $blobName from Azure Blob Storage..." -ForegroundColor Gray
az storage blob download `
    --account-name $StorageAccount `
    --container-name $Container `
    --name $blobName `
    --file $tempGz `
    --auth-mode login `
    --output none 2>$null
Write-Host "  Downloaded." -ForegroundColor Green

# ── Decompress ────────────────────────────────────────────────────────────────
Write-Host "Decompressing..." -ForegroundColor Gray
$fsIn  = [System.IO.File]::OpenRead($tempGz)
$gz    = [System.IO.Compression.GZipStream]::new($fsIn, [System.IO.Compression.CompressionMode]::Decompress)
$fsOut = [System.IO.File]::Create($tempSql)
$gz.CopyTo($fsOut)
$fsOut.Dispose(); $gz.Dispose(); $fsIn.Dispose()
$sqlMb = [math]::Round((Get-Item $tempSql).Length / 1MB, 1)
Write-Host "  Decompressed: $sqlMb MB" -ForegroundColor Green

# ── Copy into container and restore ──────────────────────────────────────────
docker cp $tempSql "${containerId}:/tmp/lughatai_restore.sql" | Out-Null

if ([int]$existing -gt 0) {
    Write-Host "Clearing existing word_definitions on Azure..." -ForegroundColor Gray
    docker compose exec -T postgres psql "$ConnStr" `
        -c "TRUNCATE TABLE word_definitions RESTART IDENTITY CASCADE;" | Out-Null
    Write-Host "  Cleared." -ForegroundColor Green
}

Write-Host "Restoring (this may take a few minutes)..." -ForegroundColor Gray
$result = docker compose exec -T postgres psql "$ConnStr" `
    -v ON_ERROR_STOP=1 -f /tmp/lughatai_restore.sql 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "Restore failed:" -ForegroundColor Red
    Write-Host $result -ForegroundColor Red
} else {
    $restored = (docker compose exec -T postgres psql "$ConnStr" -t `
        -c "SELECT COUNT(*) FROM word_definitions;" 2>$null) -join "" | ForEach-Object { $_.Trim() }
    Write-Host ""
    Write-Host "Restore complete: $restored words now on Azure." -ForegroundColor Green
}

# ── Cleanup ───────────────────────────────────────────────────────────────────
docker compose exec -T postgres rm /tmp/lughatai_restore.sql 2>$null | Out-Null
Remove-Item $tempGz, $tempSql -ErrorAction SilentlyContinue

Write-Host "Closing firewall..." -ForegroundColor Gray
az postgres flexible-server firewall-rule delete `
    --resource-group lughatai-beta-rg `
    --name lughatai-beta-db `
    --rule-name AllowLocalRestore `
    --yes --output none 2>$null | Out-Null
Write-Host "  Closed." -ForegroundColor Green
Write-Host ""
