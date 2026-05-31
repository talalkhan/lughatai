# =============================================================================
# scripts/batch_submit_openai.ps1
#
# Submits all pending word_queue words to the OpenAI Batch API.
# The Batch API processes requests asynchronously with a 24-hour SLA
# at 50% of the standard API price.
#
# What it does:
#   1. Reads all pending words from word_queue (via Docker psql)
#   2. Builds JSONL batch files (up to 14,000 requests each, ~90 MB)
#   3. Uploads each file to OpenAI Files API
#   4. Submits each file as a batch job
#   5. Marks submitted words as 'processing' in word_queue
#   6. Saves batch tracking info to scripts/words/processed/openai_batches.json
#
# Usage:
#   .\scripts\batch_submit_openai.ps1
#
# Then collect results (run after batches complete — check status with):
#   .\scripts\batch_collect_openai.ps1 -StatusOnly
#   .\scripts\batch_collect_openai.ps1
#
# Requirements:
#   - Docker running with PostgreSQL container
#   - OpenAI API key in api/appsettings.Development.json
#   - Pending words in word_queue table
# =============================================================================

param(
    # Max requests per JSONL file (OpenAI limit: 50K requests or 100 MB, whichever first)
    # 14,000 x ~6 KB/request = ~84 MB — safely under the 100 MB cap
    [int]$RequestsPerBatch = 14000,

    # Model to use for batch processing (must be Batch API-enabled)
    [string]$Model = "gpt-4o-mini",

    # Max output tokens per word
    [int]$MaxTokens = 8192,

    # Where to save batch tracking state (also read by batch_collect_openai.ps1)
    [string]$TrackingFile = (Join-Path $PSScriptRoot "words\processed\openai_batches.json"),

    # Path to settings file containing the OpenAI API key
    [string]$SettingsFile = (Join-Path $PSScriptRoot "..\api\appsettings.Development.json"),

    # Path to the AI system prompt
    [string]$PromptFile = (Join-Path $PSScriptRoot "..\api\Prompts\ai_system_prompt.txt"),

    # Extra instructions for lean core entries (applied automatically to P3+ words)
    [string]$CorePromptAddendumFile = (Join-Path $PSScriptRoot "..\api\Prompts\ai_core_prompt_addendum.txt"),

    # Temp directory for JSONL files (can be large — ~90 MB each)
    [string]$TempDir = (Join-Path $PSScriptRoot "words\processed\batch_temp"),

    # Only submit words up to this priority (0 = all priorities; 2 = P1+P2 only)
    [int]$MaxPriority = 0,

    # Only submit this many words (0 = all pending) — useful for testing
    [int]$LimitWords = 0,

    # Pause submission if estimated remaining OpenAI credit drops below this (USD)
    [double]$MinBalanceUsd = 2.0,

    # Priority tier that should switch to core-mode generation
    [int]$CoreFromPriority = 3,

    # Reasoning effort for GPT-5-family models. Use none for dictionary JSON generation.
    [string]$ReasoningEffort = "none",

    # Submit one batch then stop — for testing the full pipeline
    [switch]$TestOne
)

$ErrorActionPreference = "Stop"

# --- helpers -----------------------------------------------------------------

function Write-H([string]$t) {
    Write-Host ""; Write-Host $t -ForegroundColor Cyan
    Write-Host ("-" * $t.Length) -ForegroundColor DarkGray
}

function Write-OK([string]$m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Info([string]$m) { Write-Host "  [..] $m" -ForegroundColor White }
function Write-Warn([string]$m) { Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-Err([string]$m)  { Write-Host "  [XX] $m" -ForegroundColor Red }
function Get-WordRequest([string]$word) {
    return "English headword: $word`nUse this exact headword in the top-level `"word`" field. Do not autocorrect, normalize, or substitute a different word."
}

# --- Step 1: load config -----------------------------------------------------

Write-H "OpenAI Batch Submit"

if (-not (Test-Path $SettingsFile)) {
    Write-Err "Settings file not found: $SettingsFile"; exit 1
}
if (-not (Test-Path $PromptFile)) {
    Write-Err "Prompt file not found: $PromptFile"; exit 1
}
if (-not (Test-Path $CorePromptAddendumFile)) {
    Write-Err "Core prompt addendum file not found: $CorePromptAddendumFile"; exit 1
}

$settings     = Get-Content $SettingsFile -Encoding UTF8 | ConvertFrom-Json
$openAiKey    = $settings.AI.OpenAIApiKey
# Use .NET ReadAllText — avoids PowerShell ETS properties that corrupt ConvertTo-Json
$systemPrompt     = [System.IO.File]::ReadAllText($PromptFile, [System.Text.Encoding]::UTF8)
$coreAddendum     = [System.IO.File]::ReadAllText($CorePromptAddendumFile, [System.Text.Encoding]::UTF8)
$coreSystemPrompt = $systemPrompt + [Environment]::NewLine + [Environment]::NewLine + $coreAddendum

if ([string]::IsNullOrWhiteSpace($openAiKey) -or $openAiKey -eq "YOUR_KEY") {
    Write-Err "OpenAI API key not configured in $SettingsFile"; exit 1
}

Write-Info "Model:          $Model"
Write-Info "Max tokens:     $MaxTokens"
Write-Info "Per batch file: $RequestsPerBatch words"
Write-Info "Core threshold: P$CoreFromPriority+ -> core schema"

# --- Step 2: fetch pending words from DB -------------------------------------

Write-H "Step 1/5: Fetching pending words"

$priorityFilter = if ($MaxPriority -gt 0) { " AND priority <= $MaxPriority" } else { "" }
# Always cap the fetch to avoid piping huge result sets through Docker.
# Default cap = enough words for all batches we'll submit this run.
$fetchLimit = if ($LimitWords -gt 0) { $LimitWords } else { $RequestsPerBatch }
$sql = "SELECT id, word, priority FROM word_queue WHERE status='pending'$priorityFilter ORDER BY priority ASC, id ASC LIMIT $fetchLimit"
if ($MaxPriority -gt 0) { Write-Info "Priority filter: P1 to P$MaxPriority only" }

Write-Info "Querying word_queue..."
$rawRows = docker compose exec -T postgres psql -U postgres -d lughatai -t -A -F "`t" -c $sql 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Err "Failed to query database. Is Docker running?"; Write-Err "$rawRows"; exit 1
}

$words = @()
foreach ($row in $rawRows) {
    $row = $row.Trim()
    if ($row -eq '') { continue }
    $parts = $row -split "`t", 3
    if ($parts.Count -eq 3 -and $parts[0] -match '^\d+$' -and $parts[2] -match '^\d+$') {
        $words += [PSCustomObject]@{ Id = [int]$parts[0]; Word = $parts[1]; Priority = [int]$parts[2] }
    }
}

if ($words.Count -eq 0) {
    Write-Warn "No pending words found in word_queue. Nothing to submit."
    exit 0
}

Write-OK "Found $($words.Count) pending words"

# --- Step 3: prepare output directory ----------------------------------------

Write-H "Step 2/5: Preparing batch files"

if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
}

# JSON-escape the system prompt for embedding in JSONL.
# ConvertTo-Json serializes a string as a quoted JSON string; we strip the outer quotes.
$fullPromptJson    = $systemPrompt | ConvertTo-Json -Compress -Depth 1
$fullPromptEscaped = $fullPromptJson.Substring(1, $fullPromptJson.Length - 2)
$corePromptJson    = $coreSystemPrompt | ConvertTo-Json -Compress -Depth 1
$corePromptEscaped = $corePromptJson.Substring(1, $corePromptJson.Length - 2)

# Pre-build the request template prefix/suffix to avoid repeating the prompt each time
$reqPrefix = "{`"custom_id`":`""
# We'll build each line as: {prefix}{customId}`",{middle}{word-escaped}{suffix}
$tokenAndReasoning = if ($Model -like "gpt-5*") {
    "`"max_completion_tokens`":$MaxTokens,`"reasoning_effort`":`"$ReasoningEffort`","
} else {
    "`"max_tokens`":$MaxTokens,"
}
$reqMiddleTemplate  = "`",`"method`":`"POST`",`"url`":`"/v1/chat/completions`",`"body`":{`"model`":`"$Model`",$tokenAndReasoning`"response_format`":{`"type`":`"json_object`"},`"messages`":[{`"role`":`"system`",`"content`":`"{0}`"},{`"role`":`"user`",`"content`":`""
$reqSuffix  = "`"}]}}"
$reqMiddleByStage = @{
    enriched = $reqMiddleTemplate.Replace("{0}", $fullPromptEscaped)
    core     = $reqMiddleTemplate.Replace("{0}", $corePromptEscaped)
}

# Split words into batches
$batchCount = [Math]::Ceiling($words.Count / $RequestsPerBatch)
Write-Info "Creating $batchCount JSONL file(s) of up to $RequestsPerBatch words each"

$batchFiles = @()
for ($b = 0; $b -lt $batchCount; $b++) {
    $startIdx = $b * $RequestsPerBatch
    $endIdx   = [Math]::Min($startIdx + $RequestsPerBatch - 1, $words.Count - 1)
    $batchWords = $words[$startIdx..$endIdx]

    $jsonlPath = Join-Path $TempDir "batch_$($b+1)_of_$batchCount.jsonl"
    Write-Info "Writing batch $($b+1)/$batchCount ($($batchWords.Count) words) -> $jsonlPath"

    # UTF-8 WITHOUT BOM — OpenAI Batch API rejects files with a BOM prefix
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $sw = [System.IO.StreamWriter]::new($jsonlPath, $false, $utf8NoBom)
    try {
        foreach ($w in $batchWords) {
            # JSON-escape the user request (handles apostrophes, quotes, etc.)
            $userPromptJson    = (Get-WordRequest $w.Word) | ConvertTo-Json -Compress -Depth 1
            $userPromptEscaped = $userPromptJson.Substring(1, $userPromptJson.Length - 2)
            $stage = if ($w.Priority -ge $CoreFromPriority) { "core" } else { "enriched" }
            $customId = "wq-$($w.Id)-$stage"
            $line = $reqPrefix + $customId + $reqMiddleByStage[$stage] + $userPromptEscaped + $reqSuffix
            $sw.WriteLine($line)
        }
    } finally {
        $sw.Close()
    }

    $sizeMb = [Math]::Round((Get-Item $jsonlPath).Length / 1MB, 1)
    Write-OK "Wrote $($batchWords.Count) requests ($sizeMb MB)"
    $batchFiles += [PSCustomObject]@{
        Path        = $jsonlPath
        WordCount   = $batchWords.Count
        SizeMb      = $sizeMb
        WordIds     = $batchWords | ForEach-Object { $_.Id }
        CoreWords   = @($batchWords | Where-Object { $_.Priority -ge $CoreFromPriority }).Count
        RichWords   = @($batchWords | Where-Object { $_.Priority -lt $CoreFromPriority }).Count
    }

    if ($TestOne) { break }
}

# --- Step 4: upload and submit -----------------------------------------------

Write-H "Step 3/5: Uploading files to OpenAI"

# Load System.Net.Http assembly (required on Windows PowerShell 5.1)
Add-Type -AssemblyName "System.Net.Http"

# Build a reusable HttpClient (works on PS 5.1 and PS 7)
$httpClient = [System.Net.Http.HttpClient]::new()
$httpClient.DefaultRequestHeaders.Authorization =
    [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $openAiKey)

# Balance check — calls OpenAI organization balance API.
# Returns balance in USD, or $null if the endpoint is unavailable.
function Get-OpenAIBalance {
    try {
        $resp = $httpClient.GetAsync("https://api.openai.com/v1/organization/balance").Result
        if ($resp.IsSuccessStatusCode) {
            $body = $resp.Content.ReadAsStringAsync().Result | ConvertFrom-Json
            # Response: { "available": [{ "currency": "usd", "amount": 5.23 }] }
            $usd = $body.available | Where-Object { $_.currency -eq "usd" } | Select-Object -First 1
            if ($usd) { return [double]$usd.amount }
        }
    } catch {}
    return $null
}

$trackingData = @{
    submitted_at   = (Get-Date -Format "o")
    model          = $Model
    total_words    = $words.Count
    core_threshold = $CoreFromPriority
    batches        = @()
}

# Load existing tracking file if it exists (to append new batches)
if (Test-Path $TrackingFile) {
    Write-Info "Loading existing tracking file: $TrackingFile"
    $existing = Get-Content $TrackingFile -Encoding UTF8 | ConvertFrom-Json
    if ($existing.batches) {
        $trackingData.batches = @($existing.batches)
    }
}

$submittedCount = 0
for ($b = 0; $b -lt $batchFiles.Count; $b++) {
    $bf = $batchFiles[$b]

    # --- Balance check before each batch ---
    $balance = Get-OpenAIBalance
    if ($null -ne $balance) {
        Write-Info "OpenAI balance: `$$([Math]::Round($balance, 2))"
        if ($balance -lt $MinBalanceUsd) {
            # Save tracking file so progress is not lost
            $trackingData | ConvertTo-Json -Depth 10 | Set-Content $TrackingFile -Encoding UTF8
            Write-Warn ""
            Write-Warn "*** LOW BALANCE ALERT ***"
            Write-Warn "Balance `$$([Math]::Round($balance, 2)) is below minimum `$$MinBalanceUsd threshold."
            Write-Warn "Submitted $submittedCount words so far. Pausing to protect remaining credit."
            Write-Warn "Add credits at: https://platform.openai.com/settings/organization/billing"
            Write-Warn "Then re-run this script — it will skip already-submitted batches."
            Write-Warn ""
            break
        }
    } else {
        Write-Warn "Could not check balance (API unavailable) — continuing anyway"
    }

    Write-Info "Batch $($b+1)/$($batchFiles.Count): Uploading $($bf.SizeMb) MB file..."
    Write-Info "  Stage mix: $($bf.RichWords) enriched, $($bf.CoreWords) core"

    # Upload file to OpenAI Files API using HttpClient (works on PS 5.1 + PS 7)
    try {
        $formData = [System.Net.Http.MultipartFormDataContent]::new()

        $purposeContent = [System.Net.Http.StringContent]::new("batch")
        $formData.Add($purposeContent, "purpose")

        $fileBytes   = [System.IO.File]::ReadAllBytes($bf.Path)
        $fileContent = [System.Net.Http.ByteArrayContent]::new($fileBytes)
        $fileContent.Headers.ContentType =
            [System.Net.Http.Headers.MediaTypeHeaderValue]::new("application/octet-stream")
        $formData.Add($fileContent, "file", [System.IO.Path]::GetFileName($bf.Path))

        $uploadHttpResponse = $httpClient.PostAsync("https://api.openai.com/v1/files", $formData).Result
        $uploadBody = $uploadHttpResponse.Content.ReadAsStringAsync().Result

        if (-not $uploadHttpResponse.IsSuccessStatusCode) {
            throw "HTTP $([int]$uploadHttpResponse.StatusCode): $uploadBody"
        }
        $uploadResponse = $uploadBody | ConvertFrom-Json
    } catch {
        Write-Err "Upload failed for batch $($b+1): $($_.Exception.Message)"
        continue
    } finally {
        try { $formData.Dispose() } catch {}
    }

    $fileId = $uploadResponse.id
    Write-OK "Uploaded: file_id=$fileId"

    # Submit the batch
    Write-Info "Submitting batch job..."
    try {
        $batchBodyObj = [ordered]@{
            input_file_id     = $fileId
            endpoint          = "/v1/chat/completions"
            completion_window = "24h"
        }
        $batchBodyJson = $batchBodyObj | ConvertTo-Json -Compress

        $batchContent  = [System.Net.Http.StringContent]::new($batchBodyJson, [System.Text.Encoding]::UTF8, "application/json")
        $batchHttpResp = $httpClient.PostAsync("https://api.openai.com/v1/batches", $batchContent).Result
        $batchRespBody = $batchHttpResp.Content.ReadAsStringAsync().Result

        if (-not $batchHttpResp.IsSuccessStatusCode) {
            throw "HTTP $([int]$batchHttpResp.StatusCode): $batchRespBody"
        }
        $batchResponse = $batchRespBody | ConvertFrom-Json
    } catch {
        Write-Err "Batch submit failed for batch $($b+1): $($_.Exception.Message)"
        continue
    }

    $batchId = $batchResponse.id
    Write-OK "Submitted: batch_id=$batchId status=$($batchResponse.status)"

    # Record in tracking data (include all fields collect script will write so
    # ConvertFrom-Json PSCustomObjects have the properties on PS 5.1)
    $trackingData.batches += @{
        batch_id      = $batchId
        file_id       = $fileId
        status        = $batchResponse.status
        word_count    = $bf.WordCount
        word_ids      = $bf.WordIds
        core_words    = $bf.CoreWords
        enriched_words = $bf.RichWords
        submitted_at  = (Get-Date -Format "o")
        collected     = $false
        collected_at  = $null
        inserted      = 0
        errors        = 0
    }

    $submittedCount += $bf.WordCount

    # Mark words as processing in DB to prevent live processor re-queuing them.
    # Pipe SQL via stdin — avoids Windows 32K command-line length limit for large ID lists.
    Write-Info "Marking $($bf.WordCount) words as 'processing' in word_queue..."
    $idList    = ($bf.WordIds -join ",")
    $updateSql = "UPDATE word_queue SET status='processing', error_message='batch:submitted:$batchId', updated_at=now() WHERE id IN ($idList);"
    $updateSql | docker compose exec -T postgres psql -U postgres -d lughatai | Out-Null
    Write-OK "Marked as processing"

    # Save tracking file after each successful submission
    $trackingData | ConvertTo-Json -Depth 10 | Set-Content $TrackingFile -Encoding UTF8

    # Small delay between submissions to be polite to the API
    if ($b -lt ($batchFiles.Count - 1) -and -not $TestOne) {
        Start-Sleep -Milliseconds 500
    }
}

# --- Step 5: summary ----------------------------------------------------------

Write-H "Step 4/5: Cleaning up temp files"
# Keep JSONL files for debugging but note they're safe to delete
Write-Info "Batch JSONL files retained in: $TempDir"
Write-Info "Delete them with: Remove-Item '$TempDir\*.jsonl' to save space"

Write-H "Done!"
Write-Host ""
Write-Host "  Submitted: $submittedCount words across $($batchFiles.Count) batch jobs" -ForegroundColor Green
Write-Host "  Stage mix: $((@($words | Where-Object { $_.Priority -lt $CoreFromPriority }).Count)) enriched, $((@($words | Where-Object { $_.Priority -ge $CoreFromPriority }).Count)) core" -ForegroundColor White
Write-Host "  Tracking:  $TrackingFile" -ForegroundColor White
Write-Host ""
Write-Host "  Batches complete within 24 hours. To check status and collect results:" -ForegroundColor Cyan
Write-Host "    .\scripts\batch_collect_openai.ps1 -StatusOnly    # check progress" -ForegroundColor White
Write-Host "    .\scripts\batch_collect_openai.ps1                # collect when ready" -ForegroundColor White
Write-Host ""
