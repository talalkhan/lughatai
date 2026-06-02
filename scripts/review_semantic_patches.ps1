# =============================================================================
# scripts/review_semantic_patches.ps1
#
# QA gate for small semantic repair patches. This script does not write to Azure.
# =============================================================================

param(
    [string]$PatchDir = (Join-Path $PSScriptRoot "words\processed\gemini_semantic_patches"),
    [string]$AcceptedWordsFile = (Join-Path $PSScriptRoot "words\processed\gemini_semantic_patches_reviewed_accepted.txt"),
    [string]$RejectedCsv = (Join-Path $PSScriptRoot "words\processed\gemini_semantic_patches_reviewed_rejected.csv"),
    [string]$ReportCsv = (Join-Path $PSScriptRoot "words\processed\gemini_semantic_patches_review_report.csv"),
    [switch]$FailOnWarnings
)

$ErrorActionPreference = "Stop"

function Normalize-Roman([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return "" }
    return ($value.ToLowerInvariant() -replace "[^a-z0-9]", "")
}

function Has-Urdu([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return $false }
    return $value -match "[\u0600-\u06FF]"
}

function Has-Latin([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return $false }
    return $value -match "[A-Za-z]"
}

function Is-LikelyPluralEnglish([string]$word) {
    if ([string]::IsNullOrWhiteSpace($word)) { return $false }
    if ($word -in @("news", "series", "species", "basis", "analysis", "physics", "mathematics")) { return $false }
    return $word -match "s$"
}

function Add-Reason([System.Collections.Generic.List[string]]$list, [string]$reason) {
    if (-not [string]::IsNullOrWhiteSpace($reason)) { $list.Add($reason) | Out-Null }
}

if (-not (Test-Path $PatchDir)) { throw "Patch dir not found: $PatchDir" }

New-Item -ItemType Directory -Path (Split-Path $AcceptedWordsFile -Parent) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $RejectedCsv -Parent) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $ReportCsv -Parent) -Force | Out-Null

$files = @(Get-ChildItem $PatchDir -Filter "*.patch.json" | Sort-Object Name)
if ($files.Count -eq 0) { throw "No *.patch.json files found in $PatchDir" }

$badPrimaryExact = @(
    "کو",
    "کُو",
    "کُوپ",
    "بورڈ",
    "کیملز",
    "الکوب",
    "پیک ایکس",
    "بالاد",
    "بنگر"
)

$accepted = New-Object System.Collections.Generic.List[string]
$rows = New-Object System.Collections.Generic.List[object]

foreach ($file in $files) {
    $word = [System.IO.Path]::GetFileNameWithoutExtension($file.Name).Replace(".patch", "").Trim().ToLowerInvariant()
    $rejects = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $nastaliq = ""
    $primary = ""
    $primaryRoman = ""
    $meaningCount = 0
    $notes = ""

    try {
        $patch = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $jsonWord = ([string]$patch.word).Trim().ToLowerInvariant()
        if ($jsonWord -ne $word) { Add-Reason $rejects "word_mismatch" }

        $nastaliq = [string]$patch.script_variants.nastaliq
        $scriptRoman = [string]$patch.script_variants.roman_urdu
        $notes = [string]$patch.quality_notes

        if (-not (Has-Urdu $nastaliq)) { Add-Reason $rejects "missing_or_non_urdu_nastaliq" }
        if (Has-Latin $nastaliq) { Add-Reason $warnings "nastaliq_contains_latin" }

        $meaningCount = @($patch.meanings).Count
        if ($meaningCount -eq 0) {
            Add-Reason $rejects "missing_meanings"
        } else {
            $lead = @($patch.meanings)[0]
            $primary = [string]$lead.translations.primary
            $primaryRoman = [string]$lead.translations.primary_roman

            if (-not (Has-Urdu $primary)) { Add-Reason $rejects "lead_primary_missing_urdu" }
            if ([string]::IsNullOrWhiteSpace($primaryRoman)) { Add-Reason $rejects "lead_primary_roman_blank" }
            if ($nastaliq.Trim() -ne $primary.Trim()) { Add-Reason $rejects "nastaliq_not_equal_lead_primary" }
            if ($scriptRoman.Trim() -ne $primaryRoman.Trim()) { Add-Reason $rejects "script_roman_not_equal_lead_primary_roman" }
            if ($badPrimaryExact -contains $primary.Trim()) { Add-Reason $rejects "known_bad_primary" }
            if ($primary.Trim() -match "[()]") { Add-Reason $warnings "primary_contains_parenthetical_text" }
            if ([string]::IsNullOrWhiteSpace([string]$lead.definition_en) -or [string]::IsNullOrWhiteSpace([string]$lead.definition_ur)) {
                Add-Reason $rejects "lead_definition_blank"
            }

            if ((Is-LikelyPluralEnglish $word) -and $meaningCount -eq 1) {
                $pluralHints = @("جمع", "لوگ", "افراد", "اشخاص", "والے", "والیاں", "یں", "ات")
                $hasPluralHint = $false
                foreach ($hint in $pluralHints) {
                    if ($primary.Contains($hint) -or ([string]$lead.definition_ur).Contains($hint)) {
                        $hasPluralHint = $true
                        break
                    }
                }
                if (-not $hasPluralHint) { Add-Reason $warnings "plural_headword_may_have_singular_patch" }
            }

            $romanEqualsWord = (Normalize-Roman $primaryRoman) -eq (Normalize-Roman $word)
            if ((Is-LikelyPluralEnglish $word) -and (Normalize-Roman $primaryRoman) -eq (Normalize-Roman ($word -replace "s$", ""))) {
                Add-Reason $warnings "plural_headword_primary_roman_is_singular"
            }
            if ($romanEqualsWord) {
                $semanticAlternativeCount = 0
                foreach ($alt in @($lead.translations.alternatives)) {
                    if ((Has-Urdu ([string]$alt)) -and -not (Has-Latin ([string]$alt))) { $semanticAlternativeCount++ }
                }
                if ($semanticAlternativeCount -gt 0) {
                    Add-Reason $warnings "loanword_primary_with_semantic_alternatives"
                } else {
                    Add-Reason $warnings "loanword_primary"
                }
            }

            foreach ($m in @($patch.meanings)) {
                if ([string]::IsNullOrWhiteSpace([string]$m.pos)) { Add-Reason $rejects "meaning_pos_blank" }
                if (-not (Has-Urdu ([string]$m.definition_ur))) { Add-Reason $rejects "meaning_definition_ur_missing_urdu" }
                if ($null -eq $m.examples -or @($m.examples).Count -lt 2) {
                    Add-Reason $rejects "meaning_has_fewer_than_two_examples"
                }
                foreach ($ex in @($m.examples)) {
                    if ([string]::IsNullOrWhiteSpace([string]$ex.en) -or [string]::IsNullOrWhiteSpace([string]$ex.ur) -or [string]::IsNullOrWhiteSpace([string]$ex.roman)) {
                        Add-Reason $rejects "example_blank"
                    } elseif (-not (Has-Urdu ([string]$ex.ur))) {
                        Add-Reason $rejects "example_ur_missing_urdu"
                    }
                }
            }
        }
    } catch {
        Add-Reason $rejects ("json_parse_or_shape_error: " + $_.Exception.Message)
    }

    $status = "accepted"
    if ($rejects.Count -gt 0) {
        $status = "rejected"
    } elseif ($FailOnWarnings -and $warnings.Count -gt 0) {
        $status = "needs_review"
    }

    if ($status -eq "accepted") { $accepted.Add($word) | Out-Null }

    $rows.Add([PSCustomObject]@{
        word = $word
        status = $status
        rejects = ($rejects | Sort-Object -Unique) -join "; "
        warnings = ($warnings | Sort-Object -Unique) -join "; "
        meaning_count = $meaningCount
        nastaliq = $nastaliq
        lead_primary = $primary
        lead_primary_roman = $primaryRoman
        quality_notes = $notes
    }) | Out-Null
}

$rows | Export-Csv -Path $ReportCsv -NoTypeInformation -Encoding UTF8
$rows | Where-Object { $_.status -ne "accepted" } | Export-Csv -Path $RejectedCsv -NoTypeInformation -Encoding UTF8
$accepted | Set-Content -Path $AcceptedWordsFile -Encoding UTF8

$rejectedCount = @($rows | Where-Object { $_.status -eq "rejected" }).Count
$needsReviewCount = @($rows | Where-Object { $_.status -eq "needs_review" }).Count
$warningCount = @($rows | Where-Object { $_.warnings -ne "" }).Count

Write-Host ""
Write-Host "Semantic patch QA review" -ForegroundColor Cyan
Write-Host "------------------------" -ForegroundColor DarkGray
Write-Host "  Input patches:  $($files.Count)"
Write-Host "  Accepted:       $($accepted.Count)"
Write-Host "  Rejected:       $rejectedCount"
Write-Host "  Needs review:   $needsReviewCount"
Write-Host "  With warnings:  $warningCount"
Write-Host "  Accepted file:  $AcceptedWordsFile"
Write-Host "  Rejected CSV:   $RejectedCsv"
Write-Host "  Report CSV:     $ReportCsv"

if ($accepted.Count -eq 0) {
    throw "No accepted semantic patches after QA review."
}
