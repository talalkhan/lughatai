# =============================================================================
# scripts/status.ps1
#
# One-stop status dashboard. Shows everything at a glance and tells you
# exactly what to run next.
#
# Usage:
#   .\scripts\status.ps1
# =============================================================================

$ErrorActionPreference = "SilentlyContinue"

# ── Helpers ───────────────────────────────────────────────────────────────────
function Write-Header($text) {
    Write-Host ""
    Write-Host "  $text" -ForegroundColor DarkGray
    Write-Host ("  " + ("─" * 44)) -ForegroundColor DarkGray
}

function Write-Row($label, $value, $color = "White") {
    Write-Host ("  {0,-26} {1}" -f $label, $value) -ForegroundColor $color
}

function Write-Ok($label, $value)   { Write-Host ("  {0,-26} {1}" -f $label, "✓ $value") -ForegroundColor Green }
function Write-Warn($label, $value) { Write-Host ("  {0,-26} {1}" -f $label, "⚠ $value") -ForegroundColor Yellow }
function Write-Fail($label, $value) { Write-Host ("  {0,-26} {1}" -f $label, "✗ $value") -ForegroundColor Red }

function Sql($query) {
    $result = docker compose exec -T postgres psql -U postgres -d lughatai -t -c $query 2>$null
    return ($result -join "" ).Trim()
}

function ProgressBar($done, $total, $width = 38) {
    if ($total -eq 0) { return "[" + ("░" * $width) + "] 0%" }
    $pct    = [math]::Round($done / $total * 100)
    $filled = [math]::Round($width * $done / $total)
    $bar    = ("█" * $filled) + ("░" * ($width - $filled))
    return "[$bar] $pct%"
}

# ── Collect: track issues and build next-step list ────────────────────────────
$issues   = [System.Collections.Generic.List[string]]::new()
$nextStep = $null   # first unresolved issue becomes THE next step

# ═════════════════════════════════════════════════════════════════════════════
Clear-Host
Write-Host ""
Write-Host "  LughatAI — Project Status" -ForegroundColor Cyan
Write-Host "  ==========================" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd  HH:mm:ss')" -ForegroundColor DarkGray

# ── 1. INFRASTRUCTURE ─────────────────────────────────────────────────────────
Write-Header "INFRASTRUCTURE"

# Docker / Postgres
$pgRunning = docker compose ps --status running --services 2>$null | Select-String "postgres"
if ($pgRunning) {
    Write-Ok  "Docker (Postgres)" "running  [port 5433]"
} else {
    Write-Fail "Docker (Postgres)" "not running"
    $issues.Add("Start Docker:  docker compose up -d")
}

# DB connection + schema
$dbOk = $false
if ($pgRunning) {
    $tableCheck = docker compose exec -T postgres psql -U postgres -d lughatai -t -c `
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'word_definitions';" 2>$null
    $dbOk = ($tableCheck -join "").Trim() -eq "1"
}
if ($dbOk) {
    Write-Ok "Schema" "migrated"
} elseif ($pgRunning) {
    Write-Fail "Schema" "not migrated yet"
    $issues.Add("Run migrations:  cd api; dotnet ef database update")
} else {
    Write-Warn "Schema" "can't check (Postgres not running)"
}

# API health
$apiRunning = $false
try {
    $health = Invoke-RestMethod -Uri "http://localhost:5000/health" -TimeoutSec 2 -EA Stop
    $apiRunning = $true
    Write-Ok "API" "running  [http://localhost:5000]"
} catch {
    Write-Warn "API" "not running  (needed for word generation)"
}

# ── 2. CONFIGURATION ──────────────────────────────────────────────────────────
Write-Header "CONFIGURATION"

# Anthropic API key
$devSettings = if (Test-Path "api/appsettings.Development.json") {
    Get-Content "api/appsettings.Development.json" -Raw | ConvertFrom-Json
} else { $null }

$anthropicKey = $devSettings?.AI?.AnthropicApiKey
if ($anthropicKey -and $anthropicKey.Length -gt 10) {
    Write-Ok "Anthropic API key" "configured  (sk-ant-...$(($anthropicKey)[-4..-1] -join ''))"
} else {
    Write-Fail "Anthropic API key" "not set in appsettings.Development.json"
    $issues.Add("Add Anthropic key to api/appsettings.Development.json under AI:AnthropicApiKey")
}

# Batch processor
$batchEnabled = $devSettings?.BatchProcessor?.Enabled
if (-not $batchEnabled) {
    $batchEnabled = (Get-Content "api/appsettings.json" -Raw | ConvertFrom-Json)?.BatchProcessor?.Enabled
}
if ($batchEnabled -eq $true) {
    Write-Ok "Batch processor" "enabled"
} else {
    Write-Warn "Batch processor" "disabled"
    $issues.Add('Enable batch processor: set "BatchProcessor": { "Enabled": true } in appsettings.Development.json')
}

# ── 3. DATABASE ───────────────────────────────────────────────────────────────
Write-Header "DATABASE"

if ($dbOk) {
    $wordCount = Sql "SELECT COUNT(*) FROM word_definitions;"
    Write-Row "Words defined" $wordCount

    if ([int]$wordCount -gt 0) {
        # Breakdown by model
        $sonnetCount = Sql "SELECT COUNT(*) FROM word_definitions WHERE data->'_meta'->>'model' ILIKE '%sonnet%';"
        $haikuCount  = Sql "SELECT COUNT(*) FROM word_definitions WHERE data->'_meta'->>'model' ILIKE '%haiku%';"
        $otherCount  = Sql "SELECT COUNT(*) FROM word_definitions WHERE data->'_meta'->>'model' NOT ILIKE '%sonnet%' AND data->'_meta'->>'model' NOT ILIKE '%haiku%';"
        Write-Row "  Sonnet (premium)" $sonnetCount Gray
        Write-Row "  Haiku  (bulk)"    $haikuCount  Gray
        if ([int]$otherCount -gt 0) { Write-Row "  Other / OpenAI" $otherCount Gray }
    }
} else {
    Write-Warn "Words defined" "can't check"
}

# ── 4. WORD QUEUE ─────────────────────────────────────────────────────────────
Write-Header "WORD QUEUE"

if ($dbOk) {
    # Seeded?
    $queueTotal = Sql "SELECT COUNT(*) FROM word_queue;"
    if ([int]$queueTotal -gt 0) {
        Write-Ok "Queue seeded" "$queueTotal words loaded"
    } else {
        Write-Fail "Queue seeded" "empty — run seed script first"
        $issues.Add("Seed the queue:  Get-Content scripts/seed_word_queue.sql | docker compose exec -T postgres psql -U postgres -d lughatai")
    }

    # Stop words filtered?
    if ([int]$queueTotal -gt 0) {
        $stopWordsPresent = Sql "SELECT COUNT(*) FROM word_queue WHERE word IN ('the','be','a','in','and','or','but');"
        if ([int]$stopWordsPresent -eq 0) {
            Write-Ok "Stop words filtered" "done"
        } else {
            Write-Warn "Stop words filtered" "$stopWordsPresent function words still in queue (wasted API calls)"
            $issues.Add("Filter stop words:  Get-Content scripts/filter_stop_words.sql | docker compose exec -T postgres psql -U postgres -d lughatai")
        }
    }

    # Queue breakdown
    if ([int]$queueTotal -gt 0) {
        $pending    = Sql "SELECT COUNT(*) FROM word_queue WHERE status = 'pending';"
        $processing = Sql "SELECT COUNT(*) FROM word_queue WHERE status = 'processing';"
        $done       = Sql "SELECT COUNT(*) FROM word_queue WHERE status = 'done';"
        $failed     = Sql "SELECT COUNT(*) FROM word_queue WHERE status = 'failed';"

        Write-Host ""
        $bar = ProgressBar ([int]$done) ([int]$queueTotal)
        Write-Host "  $bar" -ForegroundColor $(if ([int]$done -eq [int]$queueTotal) { "Green" } else { "Cyan" })
        Write-Host ""
        Write-Row "  Pending"    $pending    $(if ([int]$pending    -gt 0) { "Yellow" } else { "DarkGray" })
        Write-Row "  Processing" $processing $(if ([int]$processing -gt 0) { "Cyan"   } else { "DarkGray" })
        Write-Row "  Done"       $done       $(if ([int]$done       -gt 0) { "Green"  } else { "DarkGray" })
        Write-Row "  Failed"     $failed     $(if ([int]$failed     -gt 0) { "Red"    } else { "DarkGray" })

        if ([int]$failed -gt 0) {
            $issues.Add("Retry failed words: POST http://localhost:5000/api/admin/queue/retry-failed  -H 'X-Admin-Key: dev-admin-key-change-in-production'")
        }
        if ([int]$pending -gt 0 -and $batchEnabled -eq $true -and -not $apiRunning) {
            $issues.Add("Start the API to process $pending pending words:  cd api; dotnet run")
        }
    }
} else {
    Write-Warn "Word queue" "can't check"
}

# ── 5. DOMAIN WORD LISTS ──────────────────────────────────────────────────────
Write-Header "DOMAIN WORD LISTS"

$lists = @(
    @{ Name = "islamic_religious";   File = "scripts/words/islamic_religious.txt";   Probe = "ablution";     Priority = 1 },
    @{ Name = "emotions_psychology"; File = "scripts/words/emotions_psychology.txt"; Probe = "melancholy";   Priority = 1 },
    @{ Name = "academic_formal";     File = "scripts/words/academic_formal.txt";     Probe = "paradigm";     Priority = 2 },
    @{ Name = "technology";          File = "scripts/words/technology.txt";          Probe = "blockchain";   Priority = 2 }
)

$anyListNotQueued = $false
foreach ($list in $lists) {
    if (-not $dbOk) {
        Write-Warn $list.Name "can't check"
        continue
    }
    # A word from the list is in word_queue or word_definitions → list was queued
    $inQueue = Sql "SELECT COUNT(*) FROM word_queue WHERE word = '$($list.Probe)';"
    $inDefs  = Sql "SELECT COUNT(*) FROM word_definitions WHERE word_lower = '$($list.Probe)';"
    $pri     = if ($list.Priority -eq 1) { "Priority 1 / Sonnet" } else { "Priority 2 / Haiku" }

    if ([int]$inQueue -gt 0 -or [int]$inDefs -gt 0) {
        Write-Ok $list.Name "queued  [$pri]"
    } else {
        Write-Fail $list.Name "not queued yet  [$pri]"
        $anyListNotQueued = $true
        $issues.Add("Queue domain list:  .\scripts\add_words.ps1 -File $($list.File) -Priority $($list.Priority)")
    }
}

# ── 6. BACKUP ─────────────────────────────────────────────────────────────────
Write-Header "BACKUP  (data/word_definitions_backup.sql)"

$backupFile = "data/word_definitions_backup.sql"
if (Test-Path $backupFile) {
    $backupDate  = (Get-Item $backupFile).LastWriteTime
    $backupAge   = (Get-Date) - $backupDate
    $backupWords = (Select-String -Path $backupFile -Pattern "^\d+\t" | Measure-Object).Count
    $ageStr      = if ($backupAge.TotalHours -lt 1)  { "$([math]::Round($backupAge.TotalMinutes)) min ago" } `
                   elseif ($backupAge.TotalHours -lt 24) { "$([math]::Round($backupAge.TotalHours)) hrs ago" } `
                   else { "$([math]::Round($backupAge.TotalDays)) days ago" }

    $dbWords = if ($dbOk) { [int](Sql "SELECT COUNT(*) FROM word_definitions;") } else { -1 }

    if ($dbWords -gt 0 -and $dbWords -gt $backupWords) {
        $gap = $dbWords - $backupWords
        Write-Warn "Last backup" "$ageStr  ($backupWords words backed up)"
        Write-Warn "Status" "$gap words NOT backed up yet — run .\scripts\db_backup.ps1"
        $issues.Add("Back up $gap new words:  .\scripts\db_backup.ps1  then git add / commit / push")
    } else {
        Write-Ok "Last backup" "$ageStr  ($backupWords words)"
        Write-Ok "Status" "up to date"
    }
} else {
    Write-Fail "Backup file" "not found"
    $issues.Add("Create first backup:  .\scripts\db_backup.ps1  then git add / commit / push")
}

# ── 7. NEXT STEP ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("  " + ("═" * 46)) -ForegroundColor DarkGray

if ($issues.Count -eq 0) {
    Write-Host ""
    Write-Host "  ✓  Everything looks good!" -ForegroundColor Green
    if ($dbOk) {
        $wc = Sql "SELECT COUNT(*) FROM word_definitions;"
        Write-Host "     $wc words in the database." -ForegroundColor Green
    }
} else {
    Write-Host "  NEXT STEP:" -ForegroundColor Yellow
    Write-Host ""
    # Print the single most important next step
    Write-Host "    $($issues[0])" -ForegroundColor White
    Write-Host ""

    if ($issues.Count -gt 1) {
        Write-Host "  After that:" -ForegroundColor DarkGray
        for ($i = 1; $i -lt [math]::Min($issues.Count, 4); $i++) {
            Write-Host "    $i. $($issues[$i])" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
