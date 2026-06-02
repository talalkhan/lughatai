# =============================================================================
# scripts/generate_gemini_semantic_patches.ps1
#
# Generates small semantic repair patches with Gemini. This script does not
# write to Azure and does not store API keys.
# =============================================================================

param(
    [string]$CandidateCsv = "",
    [string]$WordsFile = "",
    [int]$Limit = 25,
    [int]$ChunkSize = 10,
    [string]$Model = "gemini-2.5-flash-lite",
    [string]$ApiKey = $env:GEMINI_API_KEY,
    [string]$OutDir = (Join-Path $PSScriptRoot "words\processed\gemini_semantic_patches"),
    [string]$ReportCsv = (Join-Path $PSScriptRoot "words\processed\gemini_semantic_patches_report.csv")
)

$ErrorActionPreference = "Stop"

function Get-LatestCandidateCsv {
    $latest = Get-ChildItem (Join-Path $PSScriptRoot "words\processed\semantic_review_queue_*.csv") -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) { throw "No semantic_review_queue_*.csv found. Run export_azure_semantic_review_queue.ps1 first." }
    return $latest.FullName
}

function Get-Prompt($rowsJson) {
@"
You are an expert English-to-Urdu dictionary editor. Repair only the Urdu semantic fields for existing dictionary rows.

Rules:
- Return ONLY valid JSON. No markdown, no commentary outside JSON.
- Do not regenerate the full dictionary entry.
- Use natural Urdu meaning, not blind transliteration.
- A loanword may be primary only when it is clearly the normal Urdu usage for that exact sense.
- Put the most common learner-facing sense first.
- Separate common distinct senses when the current row is collapsed.
- Urdu examples must match the selected sense.
- Avoid nonsense loanwords, malformed Urdu, and alternatives that are related but not real translations.
- Every examples array must have exactly 2 examples.
- `script_variants.nastaliq` must exactly equal meanings[0].translations.primary.
- `script_variants.roman_urdu` must exactly equal meanings[0].translations.primary_roman.

Return this exact shape:
{
  "repairs": [
    {
      "word": "english headword",
      "script_variants": {
        "nastaliq": "primary Urdu in Nastaliq",
        "roman_urdu": "Roman Urdu"
      },
      "meanings": [
        {
          "pos": "noun|verb|adjective|adverb|etc",
          "register": "formal|informal|colloquial|literary|technical|null",
          "definition_en": "brief English definition",
          "definition_ur": "Urdu definition in Nastaliq",
          "translations": {
            "primary": "Urdu primary",
            "primary_roman": "Roman Urdu",
            "alternatives": ["Urdu alternatives"],
            "alternatives_roman": ["Roman Urdu alternatives"],
            "formal": null,
            "colloquial": null
          },
          "synonyms": { "en": [], "ur": [], "ur_roman": [] },
          "antonyms": { "en": [], "ur": [], "ur_roman": [] },
          "collocations": [],
          "examples": [
            { "en": "English sentence", "ur": "Urdu sentence", "roman": "Roman Urdu" },
            { "en": "English sentence", "ur": "Urdu sentence", "roman": "Roman Urdu" }
          ],
          "confusables": []
        }
      ],
      "quality_notes": "short explanation"
    }
  ]
}

Rows to repair:
$rowsJson
"@
}

function Invoke-Gemini($prompt) {
    $body = @{
        contents = @(
            @{
                role = "user"
                parts = @(@{ text = $prompt })
            }
        )
        generationConfig = @{
            temperature = 0.1
            responseMimeType = "application/json"
            maxOutputTokens = 12000
        }
    } | ConvertTo-Json -Depth 30

    $uri = "https://generativelanguage.googleapis.com/v1beta/models/$Model`:generateContent"
    $headers = @{ "x-goog-api-key" = $ApiKey }
    return Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -ContentType "application/json" -Body $body
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw "Gemini API key missing. Set GEMINI_API_KEY or pass -ApiKey." }

if ([string]::IsNullOrWhiteSpace($CandidateCsv) -and [string]::IsNullOrWhiteSpace($WordsFile)) {
    $CandidateCsv = Get-LatestCandidateCsv
}

$seen = @{}
$rows = @()
if (-not [string]::IsNullOrWhiteSpace($WordsFile)) {
    if (-not (Test-Path $WordsFile)) { throw "Words file not found: $WordsFile" }
    $wordRows = Get-Content $WordsFile -Encoding UTF8 |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { $_ -ne "" -and -not $_.StartsWith("#") } |
        ForEach-Object { [PSCustomObject]@{ word = $_ } }
    $rows = @($wordRows)
} else {
    if (-not (Test-Path $CandidateCsv)) { throw "Candidate CSV not found: $CandidateCsv" }
    $rows = @(Import-Csv $CandidateCsv)
}

$deduped = @()
foreach ($row in $rows) {
    $word = ([string]$row.word).Trim().ToLowerInvariant()
    if ($word -eq "" -or $seen.ContainsKey($word)) { continue }
    $seen[$word] = $true
    $deduped += [PSCustomObject]@{
        word = $word
        current_primary_ur = [string]$row.primary_ur
        current_primary_roman = [string]$row.primary_roman
        current_nastaliq = [string]$row.script_nastaliq
        current_alternatives = [string]$row.alternatives
        current_pos = [string]$row.first_pos
        current_definition_en = [string]$row.first_definition_en
        current_meaning_count = [string]$row.meaning_count
    }
}

if ($Limit -gt 0) { $deduped = @($deduped | Select-Object -First $Limit) }
if ($deduped.Count -eq 0) { throw "No candidate words." }
if ($ChunkSize -lt 1) { throw "ChunkSize must be >= 1." }

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $ReportCsv -Parent) -Force | Out-Null

$report = New-Object System.Collections.Generic.List[object]
$totalPromptTokens = 0
$totalOutputTokens = 0
$totalTokens = 0

for ($i = 0; $i -lt $deduped.Count; $i += $ChunkSize) {
    $end = [Math]::Min($i + $ChunkSize - 1, $deduped.Count - 1)
    $chunk = @($deduped[$i..$end])
    $chunkNumber = [Math]::Floor($i / $ChunkSize) + 1
    $rowsJson = $chunk | ConvertTo-Json -Depth 12
    $prompt = Get-Prompt $rowsJson

    Write-Host "Gemini patch chunk $chunkNumber words=$($chunk.Count) model=$Model"
    $response = Invoke-Gemini $prompt
    $text = [string]$response.candidates[0].content.parts[0].text
    if ([string]::IsNullOrWhiteSpace($text)) { throw "Gemini returned empty text for chunk $chunkNumber." }

    $usage = $response.usageMetadata
    $totalPromptTokens += [int]$usage.promptTokenCount
    $totalOutputTokens += [int]$usage.candidatesTokenCount
    $totalTokens += [int]$usage.totalTokenCount

    $chunkPath = Join-Path $OutDir ("chunk_{0:000}.json" -f $chunkNumber)
    [System.IO.File]::WriteAllText($chunkPath, $text, [System.Text.Encoding]::UTF8)

    try {
        $parsed = $text | ConvertFrom-Json
        foreach ($repair in @($parsed.repairs)) {
            $word = ([string]$repair.word).Trim().ToLowerInvariant()
            if ($word -eq "") { continue }
            $path = Join-Path $OutDir "$word.patch.json"
            [System.IO.File]::WriteAllText($path, ($repair | ConvertTo-Json -Depth 100), [System.Text.Encoding]::UTF8)
            $report.Add([PSCustomObject]@{
                word = $word
                status = "written"
                file = $path
                chunk = $chunkNumber
                prompt_tokens = [int]$usage.promptTokenCount
                output_tokens = [int]$usage.candidatesTokenCount
                total_tokens = [int]$usage.totalTokenCount
            }) | Out-Null
        }
    } catch {
        $report.Add([PSCustomObject]@{
            word = ($chunk.word -join "|")
            status = "parse_error"
            file = $chunkPath
            chunk = $chunkNumber
            prompt_tokens = [int]$usage.promptTokenCount
            output_tokens = [int]$usage.candidatesTokenCount
            total_tokens = [int]$usage.totalTokenCount
        }) | Out-Null
    }
}

$report | Export-Csv -Path $ReportCsv -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Gemini semantic patch generation" -ForegroundColor Cyan
Write-Host "--------------------------------" -ForegroundColor DarkGray
Write-Host "  Words requested: $($deduped.Count)"
Write-Host "  Patches written: $(@($report | Where-Object { $_.status -eq 'written' }).Count)"
Write-Host "  Model:           $Model"
Write-Host "  Prompt tokens:   $totalPromptTokens"
Write-Host "  Output tokens:   $totalOutputTokens"
Write-Host "  Total tokens:    $totalTokens"
Write-Host "  Out dir:         $OutDir"
Write-Host "  Report:          $ReportCsv"
