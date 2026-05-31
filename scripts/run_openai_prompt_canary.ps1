# =============================================================================
# scripts/run_openai_prompt_canary.ps1
#
# Generates a small read-only OpenAI canary set using the current prompt files.
# It writes JSON responses to scripts/words/processed/semantic_canary_* and does
# not insert, update, or delete any database rows.
# =============================================================================

param(
    [string]$WordsFile = (Join-Path $PSScriptRoot "words\semantic_canary_words.txt"),
    [string]$Model = "gpt-4.1-mini",
    [string]$SettingsFile = (Join-Path $PSScriptRoot "..\api\appsettings.Development.json"),
    [string]$PromptFile = (Join-Path $PSScriptRoot "..\api\Prompts\ai_system_prompt.txt"),
    [string]$CorePromptAddendumFile = (Join-Path $PSScriptRoot "..\api\Prompts\ai_core_prompt_addendum.txt"),
    [string]$OutDir = (Join-Path $PSScriptRoot "words\processed\semantic_canary"),
    [switch]$Core,
    [int]$Limit = 0
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

if (-not (Test-Path $WordsFile)) { throw "Words file not found: $WordsFile" }
if (-not (Test-Path $SettingsFile)) { throw "Settings file not found: $SettingsFile" }
if (-not (Test-Path $PromptFile)) { throw "Prompt file not found: $PromptFile" }
if ($Core -and -not (Test-Path $CorePromptAddendumFile)) { throw "Core prompt addendum not found: $CorePromptAddendumFile" }

$settings = Get-Content $SettingsFile -Encoding UTF8 | ConvertFrom-Json
$apiKey = $settings.AI.OpenAIApiKey
if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey -eq "YOUR_KEY") {
    throw "OpenAI API key not configured in $SettingsFile"
}

$systemPrompt = [System.IO.File]::ReadAllText($PromptFile, [System.Text.Encoding]::UTF8)
if ($Core) {
    $coreAddendum = [System.IO.File]::ReadAllText($CorePromptAddendumFile, [System.Text.Encoding]::UTF8)
    $systemPrompt = $systemPrompt + [Environment]::NewLine + [Environment]::NewLine + $coreAddendum
}

$seenWords = @{}
$words = @()
Get-Content $WordsFile -Encoding UTF8 |
    ForEach-Object { $_.Trim().ToLowerInvariant() } |
    Where-Object { $_ -ne "" -and -not $_.StartsWith("#") } |
    ForEach-Object {
        if (-not $seenWords.ContainsKey($_)) {
            $seenWords[$_] = $true
            $words += $_
        }
    }

if ($Limit -gt 0) { $words = @($words | Select-Object -First $Limit) }
if ($words.Count -eq 0) { throw "No canary words found in $WordsFile" }

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$summaryPath = Join-Path $OutDir ("summary_{0}.csv" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$headers = @{
    Authorization = "Bearer $apiKey"
    "Content-Type" = "application/json"
}

Write-H "OpenAI prompt canary"
Write-Host "  Model: $Model"
Write-Host "  Stage: $(if ($Core) { 'core' } else { 'enriched' })"
Write-Host "  Words: $($words.Count)"
Write-Host "  Output: $OutDir"

$rows = New-Object System.Collections.Generic.List[object]
foreach ($word in $words) {
    Write-Host "  Generating $word..." -ForegroundColor White

    $payload = @{
        model = $Model
        max_tokens = 8192
        response_format = @{ type = "json_object" }
        messages = @(
            @{ role = "system"; content = $systemPrompt },
            @{ role = "user"; content = (Get-WordRequest $word) }
        )
    } | ConvertTo-Json -Depth 20

    $response = Invoke-RestMethod `
        -Method Post `
        -Uri "https://api.openai.com/v1/chat/completions" `
        -Headers $headers `
        -Body $payload

    $content = $response.choices[0].message.content
    $parsed = $content | ConvertFrom-Json
    $safeWord = $word -replace '[^a-z0-9_-]', '_'
    $jsonPath = Join-Path $OutDir "$safeWord.json"
    [System.IO.File]::WriteAllText($jsonPath, ($parsed | ConvertTo-Json -Depth 100), [System.Text.Encoding]::UTF8)

    $meanings = @($parsed.meanings)
    $lead = if ($meanings.Count -gt 0) { $meanings[0] } else { $null }
    $rows.Add([PSCustomObject]@{
        word = $word
        json_word = $parsed.word
        nastaliq = $parsed.script_variants.nastaliq
        roman_urdu = $parsed.script_variants.roman_urdu
        meaning_count = $meanings.Count
        primary = $lead.translations.primary
        primary_roman = $lead.translations.primary_roman
        display_matches_primary = ($parsed.script_variants.nastaliq -eq $lead.translations.primary)
        alternatives = (($lead.translations.alternatives | ForEach-Object { $_ }) -join "|")
        first_definition_en = $lead.definition_en
        output_file = $jsonPath
    }) | Out-Null
}

$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $summaryPath

Write-H "Canary summary"
$rows | Format-Table word, nastaliq, meaning_count, primary, display_matches_primary, alternatives -AutoSize
Write-Host ""
Write-Host "Summary CSV: $summaryPath" -ForegroundColor Green
