# =============================================================================
# scripts/batch_collect_openai.ps1
#
# Polls OpenAI Batch API for completed batches and loads results into the DB.
# Run this after batch_submit_openai.ps1 has submitted the jobs.
#
# Usage:
#   # Check status only (no DB writes):
#   .\scripts\batch_collect_openai.ps1 -StatusOnly
#
#   # Collect completed batches and save to DB:
#   .\scripts\batch_collect_openai.ps1
#
#   # Keep polling until ALL batches finish (runs continuously):
#   .\scripts\batch_collect_openai.ps1 -Watch
#
# Each completed batch:
#   - Downloads the JSONL output file from OpenAI
#   - Parses each word's JSON response
#   - Inserts into word_definitions (ON CONFLICT UPDATE)
#   - Updates word_queue status to 'done'
#   - Marks failed words back to 'pending'
# =============================================================================

param(
    [string]$TrackingFile = (Join-Path $PSScriptRoot "words\processed\openai_batches.json"),
    [string]$SettingsFile = (Join-Path $PSScriptRoot "..\api\appsettings.Development.json"),
    [string]$TempDir      = (Join-Path $PSScriptRoot "words\processed\batch_temp"),

    # Show status only — no DB writes, no file downloads
    [switch]$StatusOnly,

    # Keep polling every N seconds until all batches are done
    [switch]$Watch,
    [int]$WatchIntervalSeconds = 120,

    # SQL batch size for DB inserts (tune if DB is slow)
    [int]$InsertBatchSize = 500
)

$ErrorActionPreference = "Stop"

function Write-H([string]$t) {
    Write-Host ""; Write-Host $t -ForegroundColor Cyan
    Write-Host ("-" * $t.Length) -ForegroundColor DarkGray
}
function Write-OK([string]$m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Info([string]$m) { Write-Host "  [..] $m" -ForegroundColor White }
function Write-Warn([string]$m) { Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-Err([string]$m)  { Write-Host "  [XX] $m" -ForegroundColor Red }

function Normalize-Headword([string]$word) {
    return $word.Trim().ToLowerInvariant()
}

function Get-QueuedWordMap([object[]]$wordIds) {
    $map = @{}
    if ($null -eq $wordIds -or $wordIds.Count -eq 0) { return $map }

    $idList = (@($wordIds) | ForEach-Object { [int]$_ }) -join ","
    $sql = "SELECT id, word FROM word_queue WHERE id IN ($idList);"
    $rawRows = $sql | docker compose exec -T postgres psql -U postgres -d lughatai -t -A -F "`t" 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to load queued words for completed batch. $rawRows"
    }

    foreach ($row in $rawRows) {
        $row = $row.Trim()
        if ($row -eq "") { continue }

        $parts = $row -split "`t", 2
        if ($parts.Count -eq 2 -and $parts[0] -match "^\d+$") {
            $map[[int]$parts[0]] = $parts[1]
        }
    }

    return $map
}

function Apply-GenerationShape([System.Text.Json.Nodes.JsonNode]$wordNode, [string]$queuedWord, [string]$stage) {
    if ($wordNode -isnot [System.Text.Json.Nodes.JsonObject]) {
        throw "Expected top-level JSON object"
    }

    # Work with explicit JsonObject cast — compound PS indexed assignment
    # ($node["a"]["b"] = $v) does NOT write back on .NET reference types in PS.
    $obj = $wordNode.AsObject()

    # Always anchor the headword to what was queued, rejecting AI drift.
    $obj.Remove("word") | Out-Null
    $obj.Add("word", [System.Text.Json.Nodes.JsonValue]::Create($queuedWord))

    # Set _meta.stage using an explicit intermediate reference.
    $metaNode = $obj["_meta"]
    if ($null -eq $metaNode) {
        $metaObj = [System.Text.Json.Nodes.JsonObject]::new()
        $obj.Add("_meta", $metaObj)
    } else {
        $metaObj = $metaNode.AsObject()
    }
    $metaObj.Remove("stage") | Out-Null
    $metaObj.Add("stage", [System.Text.Json.Nodes.JsonValue]::Create($stage))

    if ($stage -eq "core") {
        # Use .Remove() — assigning $null to a JsonObject indexer in PowerShell
        # does NOT remove the key; only .Remove() reliably does.
        foreach ($field in @("etymology", "memory_tip", "urdu_poetry", "urdu_proverb", "islamic_reference")) {
            $obj.Remove($field) | Out-Null
        }

        # Set word_family to empty array and related_words to empty object.
        $obj.Remove("word_family") | Out-Null
        $obj.Add("word_family", [System.Text.Json.Nodes.JsonArray]::new())

        $relatedWords = [System.Text.Json.Nodes.JsonObject]::new()
        $relatedWords.Add("see_also",       [System.Text.Json.Nodes.JsonArray]::new())
        $relatedWords.Add("thematic_group", [System.Text.Json.Nodes.JsonArray]::new())
        $obj.Remove("related_words") | Out-Null
        $obj.Add("related_words", $relatedWords)
    }
}

function Set-TrackingValue($target, [string]$name, $value) {
    if ($null -eq $target.PSObject.Properties[$name]) {
        $target | Add-Member -NotePropertyName $name -NotePropertyValue $value
        return
    }

    $target.$name = $value
}

# --- load config -------------------------------------------------------------

if (-not (Test-Path $TrackingFile)) {
    Write-Host "  Tracking file not found: $TrackingFile" -ForegroundColor Red
    Write-Host "  Run batch_submit_openai.ps1 first." -ForegroundColor Yellow
    exit 1
}

$settings  = Get-Content $SettingsFile -Encoding UTF8 | ConvertFrom-Json
$openAiKey = $settings.AI.OpenAIApiKey
$authHeaders = @{ "Authorization" = "Bearer $openAiKey" }

if (-not (Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir -Force | Out-Null }

# --- main loop ---------------------------------------------------------------

do {
    Write-H "OpenAI Batch Collect  $(Get-Date -Format 'HH:mm:ss')"

    $tracking = Get-Content $TrackingFile -Encoding UTF8 | ConvertFrom-Json
    $batches  = @($tracking.batches)

    $pending   = $batches | Where-Object { -not $_.collected }
    $collected = $batches | Where-Object {  $_.collected }

    Write-Info "Total batches:     $($batches.Count)"
    Write-Info "Already collected: $($collected.Count)"
    Write-Info "Remaining:         $($pending.Count)"

    if ($pending.Count -eq 0) {
        Write-OK "All batches collected! Nothing to do."
        break
    }

    # --- check status of all pending batches ---------------------------------

    Write-H "Batch status"

    $completedBatches = @()
    $failedBatches    = @()

    foreach ($b in $pending) {
        try {
            $status = Invoke-RestMethod `
                -Uri "https://api.openai.com/v1/batches/$($b.batch_id)" `
                -Headers $authHeaders `
                -Method GET

            $pct = if ($status.request_counts.total -gt 0) {
                [Math]::Round(($status.request_counts.completed / $status.request_counts.total) * 100)
            } else { 0 }

            $msg = "  [$($status.status.PadRight(12))] $($b.batch_id)  $($status.request_counts.completed)/$($status.request_counts.total) ($pct%)"

            switch ($status.status) {
                "completed"  { Write-Host $msg -ForegroundColor Green;  $completedBatches += @{tracking=$b; api=$status} }
                "failed"     { Write-Host $msg -ForegroundColor Red;    $failedBatches    += @{tracking=$b; api=$status} }
                "cancelled"  { Write-Host $msg -ForegroundColor Red;    $failedBatches    += @{tracking=$b; api=$status} }
                "expired"    { Write-Host $msg -ForegroundColor Red;    $failedBatches    += @{tracking=$b; api=$status} }
                default      { Write-Host $msg -ForegroundColor Yellow }
            }

            # Update status in tracking file
            Set-TrackingValue -target $b -name "status" -value $status.status
        } catch {
            Write-Warn "Could not check batch $($b.batch_id): $($_.Exception.Message)"
        }
    }

    # Save updated statuses
    $tracking | ConvertTo-Json -Depth 10 | Set-Content $TrackingFile -Encoding UTF8

    if ($StatusOnly) {
        Write-Host ""
        if ($completedBatches.Count -gt 0) {
            Write-Host "  $($completedBatches.Count) batch(es) ready to collect." -ForegroundColor Green
            Write-Host "  Run without -StatusOnly to collect them." -ForegroundColor White
        }
        break
    }

    # --- process completed batches -------------------------------------------

    foreach ($entry in $completedBatches) {
        $b      = $entry.tracking
        $status = $entry.api

        Write-H "Collecting batch $($b.batch_id)"
        Write-Info "Words in batch: $($b.word_count)"

        $outputFileId = $status.output_file_id
        if (-not $outputFileId) {
            Write-Warn "No output file for batch $($b.batch_id). Skipping."
            continue
        }

        # Download output JSONL
        $outputPath = Join-Path $TempDir "output_$($b.batch_id).jsonl"
        if (-not (Test-Path $outputPath)) {
            Write-Info "Downloading output file $outputFileId..."
            try {
                Invoke-RestMethod `
                    -Uri "https://api.openai.com/v1/files/$outputFileId/content" `
                    -Headers $authHeaders `
                    -OutFile $outputPath
                $sizeMb = [Math]::Round((Get-Item $outputPath).Length / 1MB, 1)
                Write-OK "Downloaded: $outputPath ($sizeMb MB)"
            } catch {
                Write-Err "Download failed: $($_.Exception.Message)"
                continue
            }
        } else {
            $sizeMb = [Math]::Round((Get-Item $outputPath).Length / 1MB, 1)
            Write-Info "Using cached download: $outputPath ($sizeMb MB)"
        }

        # Also download error file if present
        $errorFileId = $status.error_file_id
        $erroredWordIds = [System.Collections.Generic.HashSet[int]]::new()
        $requestFailureCount = 0
        if ($errorFileId) {
            $errorPath = Join-Path $TempDir "errors_$($b.batch_id).jsonl"
            Write-Info "Downloading error file $errorFileId..."
            try {
                Invoke-RestMethod `
                    -Uri "https://api.openai.com/v1/files/$errorFileId/content" `
                    -Headers $authHeaders `
                    -OutFile $errorPath
                # Parse error file to get failed word IDs
                foreach ($line in [System.IO.File]::ReadLines($errorPath)) {
                    if ($line -eq '') { continue }
                    $customId = ([System.Text.Json.JsonDocument]::Parse($line)).RootElement.GetProperty('custom_id').GetString()
                    if ($customId -match '^wq-(\d+)(?:-(core|enriched))?$') {
                        $null = $erroredWordIds.Add([int]$Matches[1])
                        $requestFailureCount++
                    }
                }
                Write-Warn "$requestFailureCount requests failed in this batch"
            } catch {
                Write-Warn "Could not download error file: $($_.Exception.Message)"
            }
        }

        # Stream-parse the output JSONL and insert into DB
        Write-Info "Parsing and inserting word definitions..."

        $queuedWordsById = Get-QueuedWordMap @($b.word_ids)

        $insertCount  = 0
        $errorCount   = 0
        $skipCount    = 0
        $jsonErrorCount = 0
        $wordMismatchCount = 0
        $missingQueueWordCount = 0
        $doneWordIds  = [System.Collections.Generic.List[int]]::new()

        # Accumulate SQL statements for batch DB writes
        $sqlInserts   = [System.Text.StringBuilder]::new()
        $sqlInserts.AppendLine("BEGIN;") | Out-Null

        $flushInserts = {
            param([System.Text.StringBuilder]$sb, [System.Collections.Generic.List[int]]$ids)
            if ($ids.Count -eq 0) { return }
            $sb.AppendLine("COMMIT;") | Out-Null
            $sql = $sb.ToString()
            $sql | docker compose exec -T postgres psql -U postgres -d lughatai --set ON_ERROR_STOP=1 | Out-Null
            $sb.Clear() | Out-Null
            $sb.AppendLine("BEGIN;") | Out-Null
            $ids.Clear()
        }

        foreach ($line in [System.IO.File]::ReadLines($outputPath)) {
            if ($line -eq '') { continue }

            $wqId = $null
            try {
                $doc = [System.Text.Json.JsonDocument]::Parse($line)
                $root = $doc.RootElement

                $customId   = $root.GetProperty('custom_id').GetString()
                $statusCode = $root.GetProperty('response').GetProperty('status_code').GetInt32()

                # Extract word_queue ID and stage from custom_id "wq-{id}-{stage}"
                if (-not ($customId -match '^wq-(\d+)(?:-(core|enriched))?$')) { $skipCount++; continue }
                $wqId = [int]$Matches[1]
                $stage = if ($Matches[2]) { $Matches[2] } else { "enriched" }
                if (-not $queuedWordsById.ContainsKey($wqId)) {
                    $errorCount++
                    $missingQueueWordCount++
                    $null = $erroredWordIds.Add($wqId)
                    continue
                }
                $queuedWord = [string]$queuedWordsById[$wqId]

                if ($statusCode -ne 200) {
                    $errorCount++
                    $requestFailureCount++
                    $null = $erroredWordIds.Add($wqId)
                    continue
                }

                # Get the AI response content
                $content = $root.GetProperty('response').GetProperty('body').GetProperty('choices')[0].GetProperty('message').GetProperty('content').GetString()

                # Extract JSON from content (strip any markdown fences or preamble)
                $jsonStart = $content.IndexOf('{')
                $jsonEnd   = $content.LastIndexOf('}')
                if ($jsonStart -lt 0 -or $jsonEnd -le $jsonStart) {
                    $errorCount++
                    $jsonErrorCount++
                    $null = $erroredWordIds.Add($wqId)
                    continue
                }
                $wordJson  = $content.Substring($jsonStart, $jsonEnd - $jsonStart + 1)

                # Validate the JSON, ensure the model kept the requested headword, and
                # enforce the stored shape for the generation stage.
                try {
                    $wasWordMismatch = $false
                    $wordNode = [System.Text.Json.Nodes.JsonNode]::Parse($wordJson)
                    if ($null -eq $wordNode) { throw "Parsed JSON node was null" }
                    $returnedWordNode = $wordNode["word"]
                    if ($null -eq $returnedWordNode) {
                        throw "Missing top-level word"
                    }

                    $returnedWord = $returnedWordNode.GetValue[string]()
                    if ([string]::IsNullOrWhiteSpace($returnedWord)) {
                        throw "Missing top-level word"
                    }

                    if ((Normalize-Headword $returnedWord) -ne (Normalize-Headword $queuedWord)) {
                        $wasWordMismatch = $true
                        $wordMismatchCount++
                        throw "Returned word '$returnedWord' did not match queued word '$queuedWord'"
                    }

                    Apply-GenerationShape -wordNode $wordNode -queuedWord $queuedWord -stage $stage
                    $wordJson = $wordNode.ToJsonString()
                } catch {
                    $errorCount++
                    if (-not $wasWordMismatch) {
                        $jsonErrorCount++
                    }
                    $null = $erroredWordIds.Add($wqId)
                    continue
                }

                # Escape the JSON for embedding in SQL (escape single quotes)
                $wordJsonEscaped = $wordJson -replace "'", "''"
                $wordNameEscaped = $queuedWord -replace "'", "''"
                $sqlInserts.AppendLine("INSERT INTO word_definitions (word, data, model)") | Out-Null
                $sqlInserts.AppendLine("VALUES ('$wordNameEscaped', '$wordJsonEscaped'::jsonb, 'gpt-4o-mini-batch')") | Out-Null
                $sqlInserts.AppendLine("ON CONFLICT (word_lower) DO UPDATE SET data = EXCLUDED.data, model = EXCLUDED.model, updated_at = now();") | Out-Null

                $doneWordIds.Add($wqId)
                $insertCount++

            } catch {
                $errorCount++
                if ($null -ne $wqId) {
                    $jsonErrorCount++
                    $null = $erroredWordIds.Add([int]$wqId)
                }
            } finally {
                try { $doc.Dispose() } catch {}
            }

            # Flush to DB every InsertBatchSize words
            if ($doneWordIds.Count -ge $InsertBatchSize) {
                # Update word_queue status for this batch
                $idList = $doneWordIds -join ","
                $sqlInserts.AppendLine("UPDATE word_queue SET status='done', error_message=NULL, updated_at=now() WHERE id IN ($idList);") | Out-Null
                & $flushInserts $sqlInserts $doneWordIds
                Write-Info "  Inserted $insertCount words so far..."
            }
        }

        # Flush remaining
        if ($doneWordIds.Count -gt 0) {
            $idList = $doneWordIds -join ","
            $sqlInserts.AppendLine("UPDATE word_queue SET status='done', error_message=NULL, updated_at=now() WHERE id IN ($idList);") | Out-Null
            & $flushInserts $sqlInserts $doneWordIds
        }

        Write-OK "Inserted $insertCount definitions"
        if ($errorCount  -gt 0) { Write-Warn "$errorCount requests had errors" }
        if ($requestFailureCount -gt 0) { Write-Warn "  Non-200 responses: $requestFailureCount" }
        if ($jsonErrorCount -gt 0) { Write-Warn "  Invalid JSON / schema issues: $jsonErrorCount" }
        if ($wordMismatchCount -gt 0) { Write-Warn "  Headword mismatches: $wordMismatchCount" }
        if ($missingQueueWordCount -gt 0) { Write-Warn "  Missing queue rows: $missingQueueWordCount" }
        if ($skipCount   -gt 0) { Write-Warn "$skipCount lines skipped (unrecognized format)" }

        # Reset errored words back to pending
        if ($erroredWordIds.Count -gt 0) {
            Write-Info "Resetting $($erroredWordIds.Count) errored words to pending..."
            $idList = (@($erroredWordIds) | Sort-Object) -join ","
            $resetSql = "UPDATE word_queue SET status='pending', attempts=0, error_message='batch:error', updated_at=now() WHERE id IN ($idList);"
            $resetSql | docker compose exec -T postgres psql -U postgres -d lughatai | Out-Null
            Write-OK "Reset to pending"
        }

        # Mark batch as collected in tracking file
        Set-TrackingValue -target $b -name "collected" -value $true
        Set-TrackingValue -target $b -name "collected_at" -value (Get-Date -Format "o")
        Set-TrackingValue -target $b -name "inserted" -value $insertCount
        Set-TrackingValue -target $b -name "errors" -value $errorCount
        $tracking | ConvertTo-Json -Depth 10 | Set-Content $TrackingFile -Encoding UTF8

        Write-OK "Batch $($b.batch_id) fully collected"
    }

    # --- handle failed batches -----------------------------------------------

    foreach ($entry in $failedBatches) {
        $b = $entry.tracking
        Write-Warn "Batch $($b.batch_id) failed/expired — resetting words to pending"
        if ($b.word_ids -and $b.word_ids.Count -gt 0) {
            $idList  = $b.word_ids -join ","
            $resetSql = "UPDATE word_queue SET status='pending', attempts=0, error_message='batch:failed', updated_at=now() WHERE id IN ($idList);"
            $resetSql | docker compose exec -T postgres psql -U postgres -d lughatai | Out-Null
            Write-OK "Reset $($b.word_ids.Count) words to pending"
        }
        Set-TrackingValue -target $b -name "collected" -value $true
        Set-TrackingValue -target $b -name "collected_at" -value (Get-Date -Format "o")
        Set-TrackingValue -target $b -name "errors" -value $b.word_count
        $tracking | ConvertTo-Json -Depth 10 | Set-Content $TrackingFile -Encoding UTF8
    }

    # --- show final queue status ---------------------------------------------

    Write-H "Queue status"
    docker compose exec -T postgres psql -U postgres -d lughatai -c "SELECT status, COUNT(*) as count FROM word_queue GROUP BY status ORDER BY status" 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

    # --- watch mode: sleep and loop ------------------------------------------

    if ($Watch) {
        $remaining = @($tracking.batches | Where-Object { -not $_.collected })
        if ($remaining.Count -eq 0) {
            Write-OK "All batches collected!"
            break
        }
        Write-Info "$($remaining.Count) batch(es) still pending. Checking again in $WatchIntervalSeconds seconds..."
        Start-Sleep -Seconds $WatchIntervalSeconds
    }

} while ($Watch)

Write-Host ""
Write-Host "  Done. Run .\scripts\db_backup.ps1 to back up the new definitions." -ForegroundColor Cyan
Write-Host ""
