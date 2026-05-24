# =============================================================================
# scripts/monitor_queue.ps1
#
# Live progress monitor for the word queue batch processor.
# Refreshes every 10 seconds until all words are done (or you press Ctrl+C).
#
# Usage:
#   .\scripts\monitor_queue.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

function Get-QueueStats {
    $rows = docker compose exec -T postgres psql -U postgres -d lughatai -t -c "
        SELECT
            status,
            COUNT(*)          AS count,
            MIN(priority)     AS min_pri,
            MAX(priority)     AS max_pri
        FROM word_queue
        GROUP BY status
        ORDER BY status;
    " 2>$null

    $stats = @{ pending = 0; processing = 0; done = 0; failed = 0 }
    foreach ($row in $rows) {
        $parts = ($row -split '\|') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        if ($parts.Count -ge 2) {
            $status = $parts[0].ToLower()
            $count  = [int]$parts[1]
            if ($stats.ContainsKey($status)) { $stats[$status] = $count }
        }
    }
    return $stats
}

function Get-WordCount {
    $result = docker compose exec -T postgres psql -U postgres -d lughatai -t -c "SELECT COUNT(*) FROM word_definitions;" 2>$null
    return (($result -join "") -replace '\s', '')
}

function Get-RecentWords {
    $rows = docker compose exec -T postgres psql -U postgres -d lughatai -t -c "
        SELECT word FROM word_definitions ORDER BY created_at DESC LIMIT 5;
    " 2>$null
    return ($rows | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

$startTime = Get-Date
$startDone = 0
$firstRun  = $true

Write-Host ""
Write-Host "UrduMeaning — Queue Monitor  (Ctrl+C to stop)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

while ($true) {
    $stats    = Get-QueueStats
    $defCount = Get-WordCount
    $recent   = Get-RecentWords
    $now      = Get-Date

    # Calculate words/min since monitor started
    $elapsed = ($now - $startTime).TotalMinutes
    if ($firstRun) { $startDone = $stats.done; $firstRun = $false }
    $rate = if ($elapsed -gt 0.1) { [math]::Round(($stats.done - $startDone) / $elapsed, 1) } else { "—" }

    # ETA
    $eta = if ($rate -gt 0 -and $stats.pending -gt 0) {
        $minsLeft = [math]::Round($stats.pending / $rate)
        if ($minsLeft -ge 60) { "$([math]::Round($minsLeft/60, 1)) hrs" } else { "$minsLeft min" }
    } else { "—" }

    Clear-Host
    Write-Host ""
    Write-Host "UrduMeaning — Queue Monitor  (Ctrl+C to stop)" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
    Write-Host ""

    $total = $stats.pending + $stats.processing + $stats.done + $stats.failed
    $pct   = if ($total -gt 0) { [math]::Round($stats.done / $total * 100) } else { 0 }

    # Progress bar
    $barWidth = 40
    $filled   = [math]::Round($barWidth * $pct / 100)
    $bar      = ("█" * $filled) + ("░" * ($barWidth - $filled))
    Write-Host "  [$bar] $pct%" -ForegroundColor Green

    Write-Host ""
    Write-Host ("  {0,-14} {1}" -f "Pending:",    $stats.pending)    -ForegroundColor Yellow
    Write-Host ("  {0,-14} {1}" -f "Processing:", $stats.processing) -ForegroundColor Cyan
    Write-Host ("  {0,-14} {1}" -f "Done:",       $stats.done)       -ForegroundColor Green
    Write-Host ("  {0,-14} {1}" -f "Failed:",     $stats.failed)     -ForegroundColor Red
    Write-Host ""
    Write-Host ("  {0,-14} {1}" -f "In DB:",      $defCount)         -ForegroundColor White
    Write-Host ("  {0,-14} {1} words/min" -f "Rate:", $rate)          -ForegroundColor Gray
    Write-Host ("  {0,-14} {1}" -f "ETA:",         $eta)             -ForegroundColor Gray

    if ($recent.Count -gt 0) {
        Write-Host ""
        Write-Host "  Last 5 words:" -ForegroundColor DarkGray
        foreach ($w in $recent) {
            Write-Host "    ✓ $w" -ForegroundColor DarkGreen
        }
    }

    if ($stats.failed -gt 0) {
        Write-Host ""
        Write-Host "  Failed words:" -ForegroundColor Red
        $failed = docker compose exec -T postgres psql -U postgres -d lughatai -t -c "
            SELECT word, error_message FROM word_queue WHERE status = 'failed' LIMIT 5;
        " 2>$null
        foreach ($row in $failed) {
            if ($row.Trim() -ne '') { Write-Host "    ✗ $($row.Trim())" -ForegroundColor Red }
        }
        Write-Host ""
        Write-Host "  To retry: POST http://localhost:5000/api/admin/queue/retry-failed" -ForegroundColor Yellow
        Write-Host "    -H 'X-Admin-Key: dev-admin-key-change-in-production'" -ForegroundColor DarkGray
    }

    if ($stats.pending -eq 0 -and $stats.processing -eq 0) {
        Write-Host ""
        Write-Host "  Queue complete! Back up now:" -ForegroundColor Green
        Write-Host "    .\scripts\db_backup.ps1" -ForegroundColor Yellow
        break
    }

    Start-Sleep -Seconds 10
}

Write-Host ""
