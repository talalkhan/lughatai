# =============================================================================
# scripts/collect_semantic_repairs_openai_batch.ps1
#
# Collects semantic repair OpenAI Batch results into JSON files and writes a
# successful words file for load_semantic_repairs_azure.ps1.
# =============================================================================

param(
    [string]$TrackingFile = (Join-Path $PSScriptRoot "words\processed\semantic_repairs_batches.json"),
    [string]$SettingsFile = (Join-Path $PSScriptRoot "..\api\appsettings.Development.json"),
    [string]$OutDir = (Join-Path $PSScriptRoot "words\processed\semantic_batch_repairs"),
    [string]$AcceptedWordsFile = (Join-Path $PSScriptRoot "words\processed\semantic_batch_repairs_accepted.txt"),
    [switch]$StatusOnly
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $TrackingFile)) { throw "Tracking file not found: $TrackingFile" }
if (-not (Test-Path $SettingsFile)) { throw "Settings file not found: $SettingsFile" }

$settings = Get-Content $SettingsFile -Encoding UTF8 | ConvertFrom-Json
$apiKey = $settings.AI.OpenAIApiKey
if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey -eq "YOUR_KEY") {
    throw "OpenAI API key not configured in $SettingsFile"
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

Add-Type -AssemblyName "System.Net.Http"
$httpClient = [System.Net.Http.HttpClient]::new()
$httpClient.DefaultRequestHeaders.Authorization =
    [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $apiKey)

$tracking = Get-Content $TrackingFile -Encoding UTF8 | ConvertFrom-Json
$acceptedWords = New-Object System.Collections.Generic.List[string]

function Set-TrackingValue($target, [string]$name, $value) {
    if ($null -eq $target.PSObject.Properties[$name]) {
        $target | Add-Member -NotePropertyName $name -NotePropertyValue $value
    } else {
        $target.$name = $value
    }
}

foreach ($batch in @($tracking.batches)) {
    $batchResp = $httpClient.GetAsync("https://api.openai.com/v1/batches/$($batch.batch_id)").Result
    $batchBody = $batchResp.Content.ReadAsStringAsync().Result
    if (-not $batchResp.IsSuccessStatusCode) { throw "Batch status failed: HTTP $([int]$batchResp.StatusCode): $batchBody" }
    $status = $batchBody | ConvertFrom-Json
    Set-TrackingValue $batch "status" $status.status
    Set-TrackingValue $batch "output_file_id" $status.output_file_id
    Set-TrackingValue $batch "error_file_id" $status.error_file_id

    Write-Host "$($batch.batch_id): $($status.status) words=$($batch.word_count)"

    if ($StatusOnly -or $status.status -ne "completed" -or $batch.collected) {
        continue
    }

    if ([string]::IsNullOrWhiteSpace($status.output_file_id)) {
        Write-Warning "Completed batch has no output_file_id: $($batch.batch_id)"
        continue
    }

    $fileResp = $httpClient.GetAsync("https://api.openai.com/v1/files/$($status.output_file_id)/content").Result
    $fileBody = $fileResp.Content.ReadAsStringAsync().Result
    if (-not $fileResp.IsSuccessStatusCode) { throw "Output download failed: HTTP $([int]$fileResp.StatusCode): $fileBody" }

    $accepted = 0
    $errors = 0
    foreach ($line in ($fileBody -split "`n")) {
        $line = $line.Trim()
        if ($line -eq "") { continue }
        try {
            $row = $line | ConvertFrom-Json
            $word = ([string]$row.custom_id).Replace("semantic__", "")
            if ($row.error) { throw "row error: $($row.error | ConvertTo-Json -Compress)" }
            $content = $row.response.body.choices[0].message.content
            if ([string]::IsNullOrWhiteSpace($content)) { throw "empty content" }
            $parsed = $content | ConvertFrom-Json
            if ($null -eq $parsed -or $parsed.word.Trim().ToLowerInvariant() -ne $word.Trim().ToLowerInvariant()) {
                throw "invalid or mismatched JSON word"
            }

            $path = Join-Path $OutDir "$word.json"
            [System.IO.File]::WriteAllText($path, ($parsed | ConvertTo-Json -Depth 100), [System.Text.Encoding]::UTF8)
            $acceptedWords.Add($word) | Out-Null
            $accepted++
        } catch {
            $errors++
            Write-Warning "Failed to collect line in $($batch.batch_id): $($_.Exception.Message)"
        }
    }

    Set-TrackingValue $batch "accepted" $accepted
    Set-TrackingValue $batch "errors" $errors
    Set-TrackingValue $batch "collected" $true
    Set-TrackingValue $batch "collected_at" (Get-Date -Format "o")
    Write-Host "Collected $accepted accepted, $errors errors from $($batch.batch_id)" -ForegroundColor Green
}

if (-not $StatusOnly -and $acceptedWords.Count -gt 0) {
    $acceptedWords | Sort-Object -Unique | Set-Content -Encoding UTF8 $AcceptedWordsFile
    Write-Host "Accepted words file: $AcceptedWordsFile" -ForegroundColor Green
}

$tracking | ConvertTo-Json -Depth 12 | Set-Content $TrackingFile -Encoding UTF8
