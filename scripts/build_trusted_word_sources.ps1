# =============================================================================
# scripts/build_trusted_word_sources.ps1
#
# Builds trusted local dictionary word sets used by build_word_quality_tiers.ps1.
#
# Sources:
#   - SCOWL 2020.12.07 release final word lists, American + English words,
#     sizes <= 70, excluding proper names, abbreviations, contractions, and
#     uppercase categories.
#   - Princeton WordNet database index files, if present.
#
# This script writes only generated files under scripts/words/processed.
# =============================================================================

param(
    [string]$OutputDir = (Join-Path $PSScriptRoot "words\processed"),
    [string]$ScowlZip = (Join-Path $PSScriptRoot "words\processed\scowl-2020.12.07.zip"),
    [string]$WordNetTarGz = (Join-Path $PSScriptRoot "words\processed\WNdb-3.0.tar.gz"),
    [string]$ScowlUrl = "https://sourceforge.net/projects/wordlist/files/SCOWL/2020.12.07/scowl-2020.12.07.zip/download",
    [string]$WordNetUrl = "https://wordnetcode.princeton.edu/3.0/WNdb-3.0.tar.gz",
    [switch]$DownloadMissing
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

function Add-Word([System.Collections.Generic.HashSet[string]]$set, [string]$word) {
    $w = $word.Trim().ToLowerInvariant()
    if (Test-AsciiLowerWord $w) { [void]$set.Add($w) }
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$scowlOut = Join-Path $OutputDir "trusted_scowl_words.txt"
$wordNetOut = Join-Path $OutputDir "trusted_wordnet_words.txt"
$combinedOut = Join-Path $OutputDir "trusted_dictionary_words.txt"
$summaryOut = Join-Path $OutputDir "trusted_word_sources_summary.txt"

if ($DownloadMissing -and -not (Test-Path $ScowlZip)) {
    Write-H "Downloading SCOWL"
    curl.exe -L $ScowlUrl -o $ScowlZip
    if ($LASTEXITCODE -ne 0) { throw "Failed to download SCOWL." }
}

if ($DownloadMissing -and -not (Test-Path $WordNetTarGz)) {
    Write-H "Downloading WordNet"
    curl.exe -L $WordNetUrl -o $WordNetTarGz
    if ($LASTEXITCODE -ne 0) { throw "Failed to download WordNet." }
}

Write-H "Building SCOWL trusted words"
$scowlWords = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if (Test-Path $ScowlZip) {
    $scowlExtractDir = Join-Path $OutputDir "scowl_release"
    if (-not (Test-Path (Join-Path $scowlExtractDir "final"))) {
        Expand-Archive -Path $ScowlZip -DestinationPath $scowlExtractDir -Force
    }

    $finalDir = Join-Path $scowlExtractDir "final"
    $levels = [System.Collections.Generic.HashSet[string]]::new([string[]]@("10","20","35","40","50","55","60","70"))
    $files = Get-ChildItem $finalDir -File |
        Where-Object {
            $_.Name -match '^(english|american)-words\.(\d\d)$' -and
            $levels.Contains($Matches[2])
        }

    foreach ($file in $files) {
        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            Add-Word $scowlWords $line
        }
    }

    $scowlWords | Sort-Object | Set-Content $scowlOut -Encoding ascii
    Write-Host "  SCOWL trusted words: $($scowlWords.Count)" -ForegroundColor Green
} else {
    Write-Host "  SCOWL zip not found: $ScowlZip" -ForegroundColor Yellow
}

Write-H "Building WordNet trusted words"
$wordNetWords = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if (Test-Path $WordNetTarGz) {
    $wordNetExtractDir = Join-Path $OutputDir "wordnet_3_0"
    if (-not (Test-Path $wordNetExtractDir)) {
        New-Item -ItemType Directory -Path $wordNetExtractDir -Force | Out-Null
        tar -xzf $WordNetTarGz -C $wordNetExtractDir
        if ($LASTEXITCODE -ne 0) { throw "Failed to extract WordNet archive." }
    }

    $indexFiles = Get-ChildItem $wordNetExtractDir -Recurse -File |
        Where-Object { $_.Name -in @("index.noun", "index.verb", "index.adj", "index.adv") }

    foreach ($file in $indexFiles) {
        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            if ($line -eq "" -or $line.StartsWith(" ")) { continue }
            $lemma = ($line -split "\s+", 2)[0].ToLowerInvariant()
            foreach ($part in ($lemma -split "_")) {
                Add-Word $wordNetWords $part
            }
            if ($lemma -notmatch "_") {
                Add-Word $wordNetWords $lemma
            }
        }
    }

    $wordNetWords | Sort-Object | Set-Content $wordNetOut -Encoding ascii
    Write-Host "  WordNet trusted words: $($wordNetWords.Count)" -ForegroundColor Green
} else {
    Write-Host "  WordNet archive not found: $WordNetTarGz" -ForegroundColor Yellow
}

Write-H "Writing combined trusted dictionary"
$combined = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($word in $scowlWords) { [void]$combined.Add($word) }
foreach ($word in $wordNetWords) { [void]$combined.Add($word) }
$combined | Sort-Object | Set-Content $combinedOut -Encoding ascii

$summary = @(
    "Generated: $(Get-Date -Format o)"
    "SCOWL zip: $ScowlZip"
    "WordNet archive: $WordNetTarGz"
    ""
    "scowl=$($scowlWords.Count)"
    "wordnet=$($wordNetWords.Count)"
    "combined=$($combined.Count)"
    ""
    "scowl file: $scowlOut"
    "wordnet file: $wordNetOut"
    "combined file: $combinedOut"
)
$summary | Set-Content $summaryOut -Encoding UTF8

Write-H "Summary"
$summary | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
