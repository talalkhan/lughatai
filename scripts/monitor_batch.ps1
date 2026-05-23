# =============================================================================
# scripts/monitor_batch.ps1
#
# Live dashboard for OpenAI batch processing progress.
# Shows batch completion %, DB queue counts, and latest collected words.
#
# Usage:
#   .\scripts\monitor_batch.ps1              # single snapshot
#   .\scripts\monitor_batch.ps1 -Watch       # refresh every 60s until done
# =============================================================================

param(
    [switch]$Watch,
    [int]$IntervalSeconds = 60
)

$SettingsFile = Join-Path $PSScriptRoot "..\api\appsettings.Development.json"
$TrackingFile = Join-Path $PSScriptRoot "words\processed\openai_batches.json"

$settings  = Get-Content $SettingsFile -Encoding UTF8 | ConvertFrom-Json
$openAiKey = $settings.AI.OpenAIApiKey
$authHdrs  = @{ Authorization = "Bearer $openAiKey" }

function Show-Dashboard {
    try { Clear-Host } catch {}
    $now = Get-Date -Format "HH:mm:ss"
    Write-Host "  LughatAI Batch Monitor  $now" -ForegroundColor Cyan
    Write-Host "  ================================" -ForegroundColor DarkGray

    # --- OpenAI batch status ---
    Write-Host ""
    Write-Host "  OPENAI BATCHES" -ForegroundColor Yellow

    if (-not (Test-Path $TrackingFile)) {
        Write-Host "  No tracking file found. Run batch_submit_openai.ps1 first." -ForegroundColor Red
    } else {
        $tracking = Get-Content $TrackingFile -Encoding UTF8 | ConvertFrom-Json
        $batches  = @($tracking.batches)

        $totalWords     = 0
        $completedWords = 0
        $allDone        = $true

        foreach ($b in $batches) {
            if ($b.collected) {
                $ins = if ($b.PSObject.Properties['inserted']) { $b.inserted } else { '?' }
                $err = if ($b.PSObject.Properties['errors'])   { $b.errors   } else { '?' }
                Write-Host ("  [COLLECTED] {0}  {1} inserted  {2} errors" -f $b.batch_id, $ins, $err) -ForegroundColor DarkGreen
                $totalWords     += $b.word_count
                $completedWords += $b.word_count
                continue
            }

            try {
                $s   = Invoke-RestMethod -Uri "https://api.openai.com/v1/batches/$($b.batch_id)" -Headers $authHdrs -Method GET
                $tot = $s.request_counts.total
                $cmp = $s.request_counts.completed
                $fld = $s.request_counts.failed
                $pct = if ($tot -gt 0) { [Math]::Round($cmp / $tot * 100) } else { 0 }

                $bar   = '#' * [Math]::Floor($pct / 5)
                $empty = '-' * (20 - $bar.Length)
                $barStr = "[$bar$empty] $pct%"

                $color = switch ($s.status) {
                    'completed' { 'Green'  }
                    'failed'    { 'Red'    }
                    'cancelled' { 'Red'    }
                    'expired'   { 'Red'    }
                    default     { 'Yellow' }
                }

                $line = "  [{0,-12}] {1}  {2}  {3} done  {4} words" -f $s.status, $b.batch_id, $barStr, $cmp, $tot
                if ($fld -gt 0) { $line += "  $fld failed" }
                Write-Host $line -ForegroundColor $color

                $totalWords     += $tot
                $completedWords += $cmp
                if ($s.status -notin 'completed','failed','cancelled','expired') { $allDone = $false }
            } catch {
                Write-Host "  [ERROR] Could not reach OpenAI for batch $($b.batch_id)" -ForegroundColor Red
                $allDone = $false
            }
        }

        if ($batches.Count -gt 1 -and $totalWords -gt 0) {
            $overall = [Math]::Round($completedWords / $totalWords * 100)
            Write-Host ""
            Write-Host ("  Overall: {0}/{1} requests ({2}%)" -f $completedWords, $totalWords, $overall) -ForegroundColor Cyan
        }
    }

    # --- DB queue counts ---
    Write-Host ""
    Write-Host "  DATABASE QUEUE" -ForegroundColor Yellow

    $rows = docker compose exec -T postgres psql -U postgres -d lughatai -t -A -F "`t" `
        -c "SELECT status, COUNT(*) FROM word_queue GROUP BY status ORDER BY status" 2>&1

    $total = 0
    foreach ($row in $rows) {
        $row = $row.Trim()
        if ($row -eq '') { continue }
        $parts = $row -split "`t"
        if ($parts.Count -ne 2) { continue }
        $status = $parts[0]; $count = [int]$parts[1]
        $total += $count
        $color = switch ($status) {
            'done'       { 'Green'  }
            'processing' { 'Yellow' }
            'pending'    { 'White'  }
            'failed'     { 'Red'    }
            default      { 'Gray'   }
        }
        Write-Host ("  {0,-12} {1,7:N0}" -f $status, $count) -ForegroundColor $color
    }
    if ($total -gt 0) {
        Write-Host ("  {0,-12} {1,7:N0}" -f "TOTAL", $total) -ForegroundColor DarkGray
    }

    # --- word_definitions count ---
    $defCount = docker compose exec -T postgres psql -U postgres -d lughatai -t -A `
        -c "SELECT COUNT(*) FROM word_definitions" 2>&1 | Where-Object { $_ -match '^\d+$' }
    if ($defCount) {
        Write-Host ""
        Write-Host ("  Definitions stored: {0:N0}" -f [int]$defCount) -ForegroundColor Cyan
    }

    # --- latest 10 collected words ---
    Write-Host ""
    Write-Host "  LATEST COLLECTED WORDS" -ForegroundColor Yellow

    $wordRows = docker compose exec -T postgres psql -U postgres -d lughatai -t -A -F "`t" `
        -c "SELECT word, model, to_char(updated_at, 'HH24:MI:SS') FROM word_definitions ORDER BY updated_at DESC LIMIT 10" 2>&1

    foreach ($row in $wordRows) {
        $row = $row.Trim()
        if ($row -eq '') { continue }
        $parts = $row -split "`t"
        if ($parts.Count -lt 2) { continue }
        Write-Host ("  {0,-20} {1,-22} {2}" -f $parts[0], $parts[1], $parts[2]) -ForegroundColor Gray
    }

    Write-Host ""
    if ($Watch) {
        Write-Host "  Refreshing every ${IntervalSeconds}s — Ctrl+C to stop" -ForegroundColor DarkGray
    }

    return $allDone
}

do {
    $done = Show-Dashboard
    if ($done -and $Watch) {
        Write-Host "  All batches complete!" -ForegroundColor Green
        break
    }
    if ($Watch) { Start-Sleep -Seconds $IntervalSeconds }
} while ($Watch)
