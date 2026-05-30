# =============================================================================
# scripts/repair_batch_headword_mismatches.ps1
#
# Repairs collected OpenAI batch rows that produced valid JSON but were rejected
# because the top-level "word" field drifted from the queued headword.
#
# This script only processes word_queue rows from the tracking file that are
# still pending with error_message='batch:error'. It anchors the JSON to the
# queued word, applies core/enriched stage shape, inserts into local Docker
# Postgres, and marks those queue rows done.
# =============================================================================

param(
    [Parameter(Mandatory)][string]$TrackingFile,
    [Parameter(Mandatory)][string]$OutputFile
)

$ErrorActionPreference = "Stop"

function Normalize-Headword([string]$word) {
    return $word.Trim().ToLowerInvariant()
}

function Apply-GenerationShape([System.Text.Json.Nodes.JsonNode]$wordNode, [string]$queuedWord, [string]$stage) {
    if ($wordNode -isnot [System.Text.Json.Nodes.JsonObject]) {
        throw "Expected top-level JSON object"
    }

    $obj = $wordNode.AsObject()
    $obj.Remove("word") | Out-Null
    $obj.Add("word", [System.Text.Json.Nodes.JsonValue]::Create($queuedWord))

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
        foreach ($field in @("etymology", "memory_tip", "urdu_poetry", "urdu_proverb", "islamic_reference")) {
            $obj.Remove($field) | Out-Null
        }

        $obj.Remove("word_family") | Out-Null
        $obj.Add("word_family", [System.Text.Json.Nodes.JsonArray]::new())

        $relatedWords = [System.Text.Json.Nodes.JsonObject]::new()
        $relatedWords.Add("see_also", [System.Text.Json.Nodes.JsonArray]::new())
        $relatedWords.Add("thematic_group", [System.Text.Json.Nodes.JsonArray]::new())
        $obj.Remove("related_words") | Out-Null
        $obj.Add("related_words", $relatedWords)
    }
}

function Invoke-LocalPsql([string]$sql) {
    $result = $sql | docker compose exec -T postgres psql -U postgres -d lughatai -v ON_ERROR_STOP=1 2>&1
    if ($LASTEXITCODE -ne 0) {
        $result | Write-Host
        throw "Local psql failed."
    }
    return $result
}

if (-not (Test-Path $TrackingFile)) { throw "Tracking file not found: $TrackingFile" }
if (-not (Test-Path $OutputFile)) { throw "Output file not found: $OutputFile" }

$tracking = Get-Content $TrackingFile -Encoding UTF8 | ConvertFrom-Json
$ids = [System.Collections.Generic.SortedSet[int]]::new()
foreach ($batch in @($tracking.batches)) {
    foreach ($id in @($batch.word_ids)) {
        [void]$ids.Add([int]$id)
    }
}

if ($ids.Count -eq 0) { throw "No word_ids found in tracking file." }

$idList = ($ids | ForEach-Object { $_.ToString() }) -join ","
$queueSql = @"
SELECT id, word, status, error_message
FROM word_queue
WHERE id IN ($idList)
ORDER BY id;
"@

$rawRows = $queueSql | docker compose exec -T postgres psql -U postgres -d lughatai -t -A -F "`t"
if ($LASTEXITCODE -ne 0) { throw "Failed to load queue rows." }

$pendingById = @{}
foreach ($row in $rawRows) {
    $line = $row.Trim()
    if ($line -eq "") { continue }

    $parts = $line -split "`t", 4
    if ($parts.Count -ne 4) { continue }
    if ($parts[2] -eq "pending" -and $parts[3] -eq "batch:error") {
        $pendingById[[int]$parts[0]] = $parts[1]
    }
}

if ($pendingById.Count -eq 0) {
    Write-Host "No pending batch:error rows found to repair." -ForegroundColor Yellow
    exit 0
}

$sqlInserts = [System.Text.StringBuilder]::new()
$doneIds = [System.Collections.Generic.List[int]]::new()
$repaired = 0
$skipped = 0

foreach ($line in [System.IO.File]::ReadLines((Resolve-Path $OutputFile))) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    try {
        $doc = [System.Text.Json.JsonDocument]::Parse($line)
        $root = $doc.RootElement
        $customId = $root.GetProperty("custom_id").GetString()
        if (-not ($customId -match '^wq-(\d+)(?:-(core|enriched))?$')) { $skipped++; continue }

        $wqId = [int]$Matches[1]
        $stage = if ($Matches[2]) { $Matches[2] } else { "enriched" }
        if (-not $pendingById.ContainsKey($wqId)) { continue }

        $queuedWord = [string]$pendingById[$wqId]
        $statusCode = $root.GetProperty("response").GetProperty("status_code").GetInt32()
        if ($statusCode -ne 200) { $skipped++; continue }

        $content = $root.GetProperty("response").GetProperty("body").GetProperty("choices")[0].GetProperty("message").GetProperty("content").GetString()
        $jsonStart = $content.IndexOf("{")
        $jsonEnd = $content.LastIndexOf("}")
        if ($jsonStart -lt 0 -or $jsonEnd -le $jsonStart) { $skipped++; continue }

        $wordJson = $content.Substring($jsonStart, $jsonEnd - $jsonStart + 1)
        $wordNode = [System.Text.Json.Nodes.JsonNode]::Parse($wordJson)
        if ($null -eq $wordNode) { $skipped++; continue }

        $returnedWordNode = $wordNode["word"]
        if ($null -eq $returnedWordNode) { $skipped++; continue }
        $returnedWord = $returnedWordNode.GetValue[string]()
        if ([string]::IsNullOrWhiteSpace($returnedWord)) { $skipped++; continue }

        if ((Normalize-Headword $returnedWord) -eq (Normalize-Headword $queuedWord)) {
            $skipped++
            continue
        }

        Apply-GenerationShape -wordNode $wordNode -queuedWord $queuedWord -stage $stage
        $anchoredJson = $wordNode.ToJsonString()

        $wordJsonEscaped = $anchoredJson -replace "'", "''"
        $wordNameEscaped = $queuedWord -replace "'", "''"
        $sqlInserts.AppendLine("INSERT INTO word_definitions (word, data, model) VALUES ('$wordNameEscaped', '$wordJsonEscaped'::jsonb, 'gpt-4o-mini-batch') ON CONFLICT (word_lower) DO UPDATE SET data = EXCLUDED.data, model = EXCLUDED.model, updated_at = now();") | Out-Null
        $doneIds.Add($wqId)
        $repaired++
    } catch {
        $skipped++
    }
}

if ($repaired -eq 0) {
    Write-Host "No repairable headword mismatches found. Skipped: $skipped" -ForegroundColor Yellow
    exit 0
}

$doneIdList = ($doneIds | ForEach-Object { $_.ToString() }) -join ","
$sql = @"
BEGIN;
$($sqlInserts.ToString())
UPDATE word_queue
SET status='done',
    error_message=NULL,
    updated_at=now()
WHERE id IN ($doneIdList);
COMMIT;

SELECT COUNT(1) AS repaired_present
FROM word_queue wq
JOIN word_definitions wd ON wd.word_lower = lower(wq.word)
WHERE wq.id IN ($doneIdList)
  AND wq.status='done'
  AND wd.model='gpt-4o-mini-batch';
"@

Invoke-LocalPsql $sql | Write-Host
Write-Host "Repaired headword mismatches: $repaired" -ForegroundColor Green
Write-Host "Skipped output rows: $skipped" -ForegroundColor Yellow
