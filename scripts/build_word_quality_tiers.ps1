# =============================================================================
# scripts/build_word_quality_tiers.ps1
#
# Builds a local quality-tier report from the generated bulk word source,
# frequency cache, and curated domain word lists.
#
# This script does NOT write to any database. It produces local files under
# scripts/words/processed so we can choose safe generation candidates before
# spending OpenAI credit.
# =============================================================================

param(
    [string]$BulkSql = (Join-Path $PSScriptRoot "words\processed\word_queue_bulk.sql"),
    [string]$FreqCache = (Join-Path $PSScriptRoot "words\processed\_freq_cache.txt"),
    [string]$WordListDir = (Join-Path $PSScriptRoot "words"),
    [string]$OutputDir = (Join-Path $PSScriptRoot "words\processed"),
    [int]$FullMaxFrequencyRank = 25000,
    [int]$CoreMaxFrequencyRank = 50000,
    [string]$ScowlWords = (Join-Path $PSScriptRoot "words\processed\trusted_scowl_words.txt"),
    [string]$WordNetWords = (Join-Path $PSScriptRoot "words\processed\trusted_wordnet_words.txt")
)

$ErrorActionPreference = "Stop"

function Write-H([string]$title) {
    Write-Host ""
    Write-Host $title -ForegroundColor Cyan
    Write-Host ("-" * $title.Length) -ForegroundColor DarkGray
}

function Test-AsciiLowerWord([string]$word) {
    if ($word.Length -lt 3 -or $word.Length -gt 64) { return $false }
    foreach ($ch in $word.ToCharArray()) {
        $code = [int][char]$ch
        if ($code -lt 97 -or $code -gt 122) { return $false }
    }
    return $true
}

if (-not (Test-Path $BulkSql)) {
    throw "Bulk SQL not found: $BulkSql. Generate it with scripts/process_word_list.ps1."
}
if (-not (Test-Path $FreqCache)) {
    throw "Frequency cache not found: $FreqCache. Run scripts/process_word_list.ps1 once to create it."
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$csvPath = Join-Path $OutputDir "word_quality_tiers.csv"
$fullPath = Join-Path $OutputDir "tier_full_candidates.txt"
$corePath = Join-Path $OutputDir "tier_core_candidates.txt"
$holdPath = Join-Path $OutputDir "tier_hold_candidates.txt"
$rejectPath = Join-Path $OutputDir "tier_reject_candidates.txt"
$summaryPath = Join-Path $OutputDir "word_quality_tiers_summary.txt"

Write-H "Loading frequency ranks"
$freqLines = [System.IO.File]::ReadAllLines((Resolve-Path $FreqCache), [System.Text.Encoding]::UTF8)
$fullFrequencyWords = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$coreFrequencyWords = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
for ($i = 0; $i -lt $freqLines.Length; $i++) {
    $line = $freqLines[$i]
    $spaceIdx = $line.IndexOf(" ")
    $word = if ($spaceIdx -gt 0) { $line.Substring(0, $spaceIdx).Trim().ToLowerInvariant() } else { $line.Trim().ToLowerInvariant() }
    if (-not (Test-AsciiLowerWord $word)) { continue }

    $rank = $i + 1
    if ($rank -le $CoreMaxFrequencyRank) {
        [void]$coreFrequencyWords.Add($word)
    }
    if ($rank -le $FullMaxFrequencyRank) {
        [void]$fullFrequencyWords.Add($word)
    }
}
Write-Host "  Full frequency words: $($fullFrequencyWords.Count)" -ForegroundColor Green
Write-Host "  Core frequency words: $($coreFrequencyWords.Count)" -ForegroundColor Green

Write-H "Loading curated domain words"
$domainSources = [System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
$domainFiles = Get-ChildItem $WordListDir -File -Filter *.txt | Sort-Object Name
foreach ($file in $domainFiles) {
    foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
        $word = $line.Trim().ToLowerInvariant()
        if ($word -eq "" -or $word.StartsWith("#")) { continue }
        if (-not (Test-AsciiLowerWord $word)) { continue }
        if (-not ($domainSources.ContainsKey($word))) {
            $domainSources.Add($word, [System.Collections.Generic.List[string]]::new())
        }
        $domainSources[$word].Add($file.BaseName)
    }
}
Write-Host "  Curated domain words: $($domainSources.Count)" -ForegroundColor Green

Write-H "Loading trusted dictionary words"
$trustedWords = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$trustedSources = [System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Add-TrustedWord([string]$word, [string]$source) {
    $w = $word.Trim().ToLowerInvariant()
    if (-not (Test-AsciiLowerWord $w)) { return }
    [void]$trustedWords.Add($w)
    if (-not ($trustedSources.ContainsKey($w))) {
        $trustedSources.Add($w, [System.Collections.Generic.List[string]]::new())
    }
    $trustedSources[$w].Add($source)
}

if (Test-Path $ScowlWords) {
    foreach ($line in [System.IO.File]::ReadLines((Resolve-Path $ScowlWords))) {
        Add-TrustedWord $line "scowl"
    }
    Write-Host "  SCOWL words loaded from: $ScowlWords" -ForegroundColor White
} else {
    Write-Host "  SCOWL words file not found: $ScowlWords" -ForegroundColor Yellow
}

if (Test-Path $WordNetWords) {
    foreach ($line in [System.IO.File]::ReadLines((Resolve-Path $WordNetWords))) {
        Add-TrustedWord $line "wordnet"
    }
    Write-Host "  WordNet words loaded from: $WordNetWords" -ForegroundColor White
} else {
    Write-Host "  WordNet words file not found: $WordNetWords" -ForegroundColor Yellow
}

Write-Host "  Trusted dictionary words: $($trustedWords.Count)" -ForegroundColor Green

Write-H "Parsing bulk source and classifying"
$rx = [regex]"^\s*\('([^']+)',\s*([1-5])\),?"
$sourceWords = [System.Collections.Generic.Dictionary[string,int]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($line in [System.IO.File]::ReadLines((Resolve-Path $BulkSql))) {
    $match = $rx.Match($line)
    if (-not $match.Success) { continue }

    $word = $match.Groups[1].Value.Trim().ToLowerInvariant()
    $priority = [int]$match.Groups[2].Value
    if ($word -eq "") { continue }

    if ($sourceWords.ContainsKey($word)) {
        if ($priority -lt $sourceWords[$word]) { $sourceWords[$word] = $priority }
    } else {
        $sourceWords.Add($word, $priority)
    }
}
Write-Host "  Bulk source words: $($sourceWords.Count)" -ForegroundColor Green

$rows = [System.Collections.Generic.List[object]]::new($sourceWords.Count)
$full = [System.Collections.Generic.List[string]]::new()
$core = [System.Collections.Generic.List[string]]::new()
$hold = [System.Collections.Generic.List[string]]::new()
$reject = [System.Collections.Generic.List[string]]::new()

foreach ($entry in $sourceWords.GetEnumerator()) {
    $word = $entry.Key
    $sourcePriority = $entry.Value
    $isFullFrequency = $fullFrequencyWords.Contains($word)
    $isCoreFrequency = $coreFrequencyWords.Contains($word)
    $frequencyBucket = if ($isFullFrequency) { "full" } elseif ($isCoreFrequency) { "core" } else { "" }
    $domainValue = if ($domainSources.ContainsKey($word)) { ($domainSources[$word] | Sort-Object -Unique) -join ";" } else { "" }
    $trustedValue = if ($trustedSources.ContainsKey($word)) { ($trustedSources[$word] | Sort-Object -Unique) -join ";" } else { "" }

    $mode = "hold"
    $tierReason = "long_tail_unvalidated"

    if (-not (Test-AsciiLowerWord $word)) {
        $mode = "reject"
        $tierReason = "invalid_token_shape"
    } elseif ($domainValue -ne "") {
        $mode = "full"
        $tierReason = "curated_domain_list"
    } elseif ($isFullFrequency) {
        $mode = "full"
        $tierReason = "frequency_rank_le_$FullMaxFrequencyRank"
    } elseif ($sourcePriority -le 2) {
        $mode = "full"
        $tierReason = "source_priority_$sourcePriority"
    } elseif ($isCoreFrequency) {
        $mode = "core"
        $tierReason = "frequency_rank_le_$CoreMaxFrequencyRank"
    } elseif ($trustedWords.Contains($word)) {
        $mode = "core"
        $tierReason = "trusted_dictionary"
    }

    switch ($mode) {
        "full"   { $full.Add($word) }
        "core"   { $core.Add($word) }
        "hold"   { $hold.Add($word) }
        "reject" { $reject.Add($word) }
    }

    $rows.Add([PSCustomObject]@{
        word            = $word
        generation_mode = $mode
        reason          = $tierReason
        source_priority = $sourcePriority
        frequency_bucket = $frequencyBucket
        domain_sources  = $domainValue
        trusted_sources  = $trustedValue
    })
}

$orderedRows = $rows | Sort-Object @{Expression="generation_mode"; Ascending=$true}, @{Expression="frequency_bucket"; Ascending=$true}, word
$orderedRows | Export-Csv $csvPath -NoTypeInformation -Encoding UTF8

$full   | Sort-Object -Unique | Set-Content $fullPath -Encoding ascii
$core   | Sort-Object -Unique | Set-Content $corePath -Encoding ascii
$hold   | Sort-Object -Unique | Set-Content $holdPath -Encoding ascii
$reject | Sort-Object -Unique | Set-Content $rejectPath -Encoding ascii

$summary = @(
    "Generated: $(Get-Date -Format o)"
    "Bulk source: $BulkSql"
    "Frequency cache: $FreqCache"
    "Domain list dir: $WordListDir"
    "SCOWL words: $ScowlWords"
    "WordNet words: $WordNetWords"
    ""
    "total=$($sourceWords.Count)"
    "full=$($full.Count)"
    "core=$($core.Count)"
    "hold=$($hold.Count)"
    "reject=$($reject.Count)"
    ""
    "full file: $fullPath"
    "core file: $corePath"
    "hold file: $holdPath"
    "reject file: $rejectPath"
    "csv file: $csvPath"
)
$summary | Set-Content $summaryPath -Encoding UTF8

Write-H "Summary"
$summary | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
