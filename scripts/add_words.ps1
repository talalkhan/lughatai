# =============================================================================
# scripts/add_words.ps1
#
# Queues a list of words for AI generation from a plain text file.
# One word (or phrase) per line. Lines starting with # are comments.
# Words already in the queue or already defined are silently skipped.
#
# Usage:
#   .\scripts\add_words.ps1 -File scripts\words\technology.txt
#   .\scripts\add_words.ps1 -File scripts\words\medical.txt -Priority 1
#   .\scripts\add_words.ps1 -File scripts\words\islamic.txt -Priority 1 -ApiUrl http://localhost:5000
#
# Priority:
#   1 = Sonnet (high quality, slower, more expensive) — use for important words
#   2 = Haiku  (good quality, fast, cheap)            — default, good for bulk
#   3 = Haiku  (lower priority, processed last)
# =============================================================================

param(
    [Parameter(Mandatory)][string] $File,
    [ValidateRange(1,5)][int]      $Priority = 2,
    [string]                       $ApiUrl   = "http://localhost:5000",
    [string]                       $AdminKey = "dev-admin-key-change-in-production"
)

$ErrorActionPreference = "Stop"

# ── 1. Read and clean the word list ──────────────────────────────────────────
if (-not (Test-Path $File)) {
    Write-Host "File not found: $File" -ForegroundColor Red
    exit 1
}

$words = Get-Content $File -Encoding UTF8 |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne '' -and -not $_.StartsWith('#') } |
    Sort-Object -Unique

Write-Host ""
Write-Host "LughatAI — Add Words" -ForegroundColor Cyan
Write-Host "====================" -ForegroundColor Cyan
Write-Host "  File:     $File" -ForegroundColor Gray
Write-Host "  Words:    $($words.Count)" -ForegroundColor Gray
Write-Host "  Priority: $Priority $(if ($Priority -eq 1) { '(Sonnet)' } else { '(Haiku)' })" -ForegroundColor Gray
Write-Host "  API:      $ApiUrl" -ForegroundColor Gray
Write-Host ""

if ($words.Count -eq 0) {
    Write-Host "No words found in file." -ForegroundColor Yellow
    exit 0
}

# ── 2. Send to admin API in batches of 100 ───────────────────────────────────
$batchSize = 100
$totalAdded = 0
$batches = [math]::Ceiling($words.Count / $batchSize)

for ($i = 0; $i -lt $words.Count; $i += $batchSize) {
    $batch     = $words[$i..([math]::Min($i + $batchSize - 1, $words.Count - 1))]
    $batchNum  = [math]::Floor($i / $batchSize) + 1
    $body      = @{ words = $batch; priority = $Priority } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod `
            -Method POST `
            -Uri "$ApiUrl/api/admin/queue/add" `
            -Headers @{ 'X-Admin-Key' = $AdminKey; 'Content-Type' = 'application/json' } `
            -Body $body

        $totalAdded += $response.added
        Write-Host "  Batch $batchNum/$batches — queued $($response.added) words" -ForegroundColor Green
    }
    catch {
        Write-Host "  Batch $batchNum/$batches — FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Is the API running? cd api; dotnet run" -ForegroundColor Yellow
        exit 1
    }
}

# ── 3. Summary ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Done. $totalAdded words queued at priority $Priority." -ForegroundColor Green
Write-Host "(Words already in queue or already defined were skipped automatically.)" -ForegroundColor Gray
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Make sure the API is running with BatchProcessor:Enabled = true" -ForegroundColor White
Write-Host "  2. Watch progress:  .\scripts\monitor_queue.ps1" -ForegroundColor White
Write-Host "  3. When done:       .\scripts\db_backup.ps1" -ForegroundColor White
Write-Host ""
