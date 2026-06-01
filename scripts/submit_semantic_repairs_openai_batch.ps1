# =============================================================================
# scripts/submit_semantic_repairs_openai_batch.ps1
#
# Submits semantic repair candidates to the OpenAI Batch API.
# This does not write to Azure. Collect results with
# collect_semantic_repairs_openai_batch.ps1, then load reviewed results with
# load_semantic_repairs_azure.ps1.
# =============================================================================

param(
    [string]$CandidateCsv = "",
    [string]$WordsFile = "",
    [int]$Limit = 100,
    [int]$RequestsPerBatch = 100,
    [string]$Model = "gpt-5.5",
    [int]$MaxCompletionTokens = 20000,
    [string]$ReasoningEffort = "none",
    [string]$SettingsFile = (Join-Path $PSScriptRoot "..\api\appsettings.Development.json"),
    [string]$PromptFile = (Join-Path $PSScriptRoot "..\api\Prompts\ai_system_prompt.txt"),
    [string]$TrackingFile = (Join-Path $PSScriptRoot "words\processed\semantic_repairs_batches.json"),
    [string]$TempDir = (Join-Path $PSScriptRoot "words\processed\semantic_repair_batch_temp")
)

$ErrorActionPreference = "Stop"

function Write-H([string]$Text) {
    Write-Host ""
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ("-" * $Text.Length) -ForegroundColor DarkGray
}

function Get-WordRequest([string]$Word) {
    return "English headword: $Word`nUse this exact headword in the top-level `"word`" field. Do not autocorrect, normalize, or substitute a different word."
}

function Get-LatestCandidateCsv {
    $latest = Get-ChildItem (Join-Path $PSScriptRoot "words\processed\semantic_review_queue_*.csv") -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) { throw "No semantic_review_queue_*.csv found. Run export_azure_semantic_review_queue.ps1 first." }
    return $latest.FullName
}

if (-not (Test-Path $SettingsFile)) { throw "Settings file not found: $SettingsFile" }
if (-not (Test-Path $PromptFile)) { throw "Prompt file not found: $PromptFile" }

$settings = Get-Content $SettingsFile -Encoding UTF8 | ConvertFrom-Json
$apiKey = $settings.AI.OpenAIApiKey
if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey -eq "YOUR_KEY") {
    throw "OpenAI API key not configured in $SettingsFile"
}

$seen = @{}
$words = @()
if (-not [string]::IsNullOrWhiteSpace($WordsFile)) {
    if (-not (Test-Path $WordsFile)) { throw "Words file not found: $WordsFile" }
    Get-Content $WordsFile -Encoding UTF8 |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { $_ -ne "" -and -not $_.StartsWith("#") } |
        ForEach-Object {
            if (-not $seen.ContainsKey($_)) {
                $seen[$_] = $true
                $words += $_
            }
        }
} else {
    if ([string]::IsNullOrWhiteSpace($CandidateCsv)) { $CandidateCsv = Get-LatestCandidateCsv }
    if (-not (Test-Path $CandidateCsv)) { throw "Candidate CSV not found: $CandidateCsv" }
    Import-Csv $CandidateCsv |
        ForEach-Object { $_.word.Trim().ToLowerInvariant() } |
        Where-Object { $_ -ne "" } |
        ForEach-Object {
            if (-not $seen.ContainsKey($_)) {
                $seen[$_] = $true
                $words += $_
            }
        }
}

if ($Limit -gt 0) { $words = @($words | Select-Object -First $Limit) }
if ($words.Count -eq 0) { throw "No words to submit." }

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $TrackingFile -Parent) -Force | Out-Null

$systemPrompt = [System.IO.File]::ReadAllText($PromptFile, [System.Text.Encoding]::UTF8)
$tokenAndReasoning = if ($Model -like "gpt-5*") {
    "`"max_completion_tokens`":$MaxCompletionTokens,`"reasoning_effort`":`"$ReasoningEffort`","
} else {
    "`"max_tokens`":$MaxCompletionTokens,"
}
$systemPromptJson = $systemPrompt | ConvertTo-Json -Compress -Depth 1
$systemPromptEscaped = $systemPromptJson.Substring(1, $systemPromptJson.Length - 2)

Write-H "Submit semantic repair batch"
Write-Host "  Words:   $($words.Count)"
Write-Host "  Model:   $Model"
Write-Host "  Per file: $RequestsPerBatch"
Write-Host "  Tracking: $TrackingFile"

$batchFiles = @()
$batchCount = [Math]::Ceiling($words.Count / $RequestsPerBatch)
for ($b = 0; $b -lt $batchCount; $b++) {
    $start = $b * $RequestsPerBatch
    $end = [Math]::Min($start + $RequestsPerBatch - 1, $words.Count - 1)
    $batchWords = @($words[$start..$end])
    $jsonlPath = Join-Path $TempDir ("semantic_repair_{0}_of_{1}.jsonl" -f ($b + 1), $batchCount)

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $sw = [System.IO.StreamWriter]::new($jsonlPath, $false, $utf8NoBom)
    try {
        foreach ($word in $batchWords) {
            $userPromptJson = (Get-WordRequest $word) | ConvertTo-Json -Compress -Depth 1
            $userPromptEscaped = $userPromptJson.Substring(1, $userPromptJson.Length - 2)
            $line = "{`"custom_id`":`"semantic__$word`",`"method`":`"POST`",`"url`":`"/v1/chat/completions`",`"body`":{`"model`":`"$Model`",$tokenAndReasoning`"response_format`":{`"type`":`"json_object`"},`"messages`":[{`"role`":`"system`",`"content`":`"$systemPromptEscaped`"},{`"role`":`"user`",`"content`":`"$userPromptEscaped`"}]}}"
            $sw.WriteLine($line)
        }
    } finally {
        $sw.Close()
    }

    $batchFiles += [PSCustomObject]@{
        Path = $jsonlPath
        WordCount = $batchWords.Count
        Words = $batchWords
        SizeMb = [Math]::Round((Get-Item $jsonlPath).Length / 1MB, 2)
    }
}

Add-Type -AssemblyName "System.Net.Http"
$httpClient = [System.Net.Http.HttpClient]::new()
$httpClient.DefaultRequestHeaders.Authorization =
    [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $apiKey)

$tracking = [ordered]@{
    submitted_at = (Get-Date -Format "o")
    model = $Model
    max_completion_tokens = $MaxCompletionTokens
    reasoning_effort = $ReasoningEffort
    total_words = $words.Count
    batches = @()
}

foreach ($bf in $batchFiles) {
    Write-Host "Uploading $($bf.WordCount) words ($($bf.SizeMb) MB): $($bf.Path)"
    $formData = [System.Net.Http.MultipartFormDataContent]::new()
    try {
        $formData.Add([System.Net.Http.StringContent]::new("batch"), "purpose")
        $fileBytes = [System.IO.File]::ReadAllBytes($bf.Path)
        $fileContent = [System.Net.Http.ByteArrayContent]::new($fileBytes)
        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new("application/octet-stream")
        $formData.Add($fileContent, "file", [System.IO.Path]::GetFileName($bf.Path))

        $uploadResp = $httpClient.PostAsync("https://api.openai.com/v1/files", $formData).Result
        $uploadBody = $uploadResp.Content.ReadAsStringAsync().Result
        if (-not $uploadResp.IsSuccessStatusCode) { throw "Upload failed: HTTP $([int]$uploadResp.StatusCode): $uploadBody" }
        $upload = $uploadBody | ConvertFrom-Json
    } finally {
        try { $formData.Dispose() } catch {}
    }

    $batchPayload = @{
        input_file_id = $upload.id
        endpoint = "/v1/chat/completions"
        completion_window = "24h"
    } | ConvertTo-Json -Compress
    $content = [System.Net.Http.StringContent]::new($batchPayload, [System.Text.Encoding]::UTF8, "application/json")
    $batchResp = $httpClient.PostAsync("https://api.openai.com/v1/batches", $content).Result
    $batchBody = $batchResp.Content.ReadAsStringAsync().Result
    if (-not $batchResp.IsSuccessStatusCode) { throw "Batch submit failed: HTTP $([int]$batchResp.StatusCode): $batchBody" }
    $batch = $batchBody | ConvertFrom-Json

    Write-Host "Submitted batch $($batch.id) status=$($batch.status)" -ForegroundColor Green
    $tracking.batches += [ordered]@{
        batch_id = $batch.id
        file_id = $upload.id
        status = $batch.status
        word_count = $bf.WordCount
        words = $bf.Words
        submitted_at = (Get-Date -Format "o")
        collected = $false
        output_file_id = $null
        error_file_id = $null
        accepted = 0
        errors = 0
    }
}

$tracking | ConvertTo-Json -Depth 12 | Set-Content $TrackingFile -Encoding UTF8
Write-Host "Tracking saved: $TrackingFile" -ForegroundColor Green
