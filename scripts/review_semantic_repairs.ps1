# =============================================================================
# scripts/review_semantic_repairs.ps1
#
# Pre-load QA gate for semantic repair JSON.
# Writes accepted words plus a CSV report with warnings/reject reasons.
# =============================================================================

param(
    [string]$WordsFile = (Join-Path $PSScriptRoot "words\processed\semantic_batch_repairs_accepted.txt"),
    [string]$InputDir = (Join-Path $PSScriptRoot "words\processed\semantic_batch_repairs"),
    [string]$AcceptedWordsFile = (Join-Path $PSScriptRoot "words\processed\semantic_batch_repairs_reviewed_accepted.txt"),
    [string]$RejectedCsv = (Join-Path $PSScriptRoot "words\processed\semantic_batch_repairs_reviewed_rejected.csv"),
    [string]$ReportCsv = (Join-Path $PSScriptRoot "words\processed\semantic_batch_repairs_review_report.csv"),
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

function Add-Reason([System.Collections.Generic.List[string]]$list, [string]$reason) {
    if (-not [string]::IsNullOrWhiteSpace($reason)) { $list.Add($reason) | Out-Null }
}

if (-not (Test-Path $WordsFile)) { throw "Words file not found: $WordsFile" }
if (-not (Test-Path $InputDir)) { throw "Input dir not found: $InputDir" }

New-Item -ItemType Directory -Path (Split-Path $AcceptedWordsFile -Parent) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $RejectedCsv -Parent) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $ReportCsv -Parent) -Force | Out-Null

$words = Get-Content $WordsFile -Encoding UTF8 |
    ForEach-Object { $_.Trim().ToLowerInvariant() } |
    Where-Object { $_ -ne "" -and -not $_.StartsWith("#") } |
    Sort-Object -Unique

if ($words.Count -eq 0) { throw "No words found in $WordsFile" }

$accepted = New-Object System.Collections.Generic.List[string]
$rows = New-Object System.Collections.Generic.List[object]

foreach ($word in $words) {
    $rejects = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $primary = ""
    $primaryRoman = ""
    $nastaliq = ""
    $meaningCount = 0
    $leadDefinition = ""

    $path = Join-Path $InputDir "$word.json"
    if (-not (Test-Path $path)) {
        Add-Reason $rejects "missing_json_file"
    } else {
        try {
            $json = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($json.word.Trim().ToLowerInvariant() -ne $word) {
                Add-Reason $rejects "top_level_word_mismatch"
            }

            $nastaliq = [string]$json.script_variants.nastaliq
            if (-not (Has-Urdu $nastaliq)) {
                Add-Reason $rejects "missing_or_non_urdu_nastaliq"
            }
            if (Has-Latin $nastaliq) {
                Add-Reason $warnings "nastaliq_contains_latin"
            }

            $meaningCount = @($json.meanings).Count
            if ($meaningCount -eq 0) {
                Add-Reason $rejects "missing_meanings"
            } else {
                $lead = @($json.meanings)[0]
                $primary = [string]$lead.translations.primary
                $primaryRoman = [string]$lead.translations.primary_roman
                $leadDefinition = [string]$lead.definition_en

                if (-not (Has-Urdu $primary)) {
                    Add-Reason $rejects "lead_primary_missing_urdu"
                }
                if ([string]::IsNullOrWhiteSpace($primaryRoman)) {
                    Add-Reason $rejects "lead_primary_roman_blank"
                }
                if ([string]::IsNullOrWhiteSpace($lead.definition_en) -or [string]::IsNullOrWhiteSpace($lead.definition_ur)) {
                    Add-Reason $rejects "lead_definition_blank"
                }
                if ($nastaliq.Trim() -ne "" -and $primary.Trim() -ne "" -and $nastaliq.Trim() -ne $primary.Trim()) {
                    Add-Reason $warnings "nastaliq_differs_from_lead_primary_loader_will_normalize"
                }

                $romanEqualsWord = (Normalize-Roman $primaryRoman) -eq (Normalize-Roman $word)
                if ($romanEqualsWord) {
                    $semanticAlternativeCount = 0
                    foreach ($alt in @($lead.translations.alternatives)) {
                        if ((Has-Urdu ([string]$alt)) -and -not (Has-Latin ([string]$alt))) {
                            $semanticAlternativeCount++
                        }
                    }
                    if ($semanticAlternativeCount -gt 0) {
                        Add-Reason $warnings "loanword_or_transliteration_primary_with_semantic_alternatives"
                    } else {
                        Add-Reason $warnings "loanword_or_transliteration_primary"
                    }
                }

                if ($meaningCount -eq 1 -and @($lead.confusables).Count -eq 0) {
                    Add-Reason $warnings "thin_single_meaning_no_confusables"
                }

                foreach ($m in @($json.meanings)) {
                    if ([string]::IsNullOrWhiteSpace([string]$m.pos)) { Add-Reason $rejects "meaning_pos_blank" }
                    if ($null -eq $m.examples -or @($m.examples).Count -lt 2) { Add-Reason $warnings "meaning_has_fewer_than_two_examples" }
                    foreach ($ex in @($m.examples)) {
                        if ([string]::IsNullOrWhiteSpace([string]$ex.en) -or [string]::IsNullOrWhiteSpace([string]$ex.ur)) {
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
    }

    $status = "accepted"
    if ($rejects.Count -gt 0) {
        $status = "rejected"
    } elseif ($FailOnWarnings -and $warnings.Count -gt 0) {
        $status = "needs_review"
    }

    if ($status -eq "accepted") {
        $accepted.Add($word) | Out-Null
    }

    $rows.Add([PSCustomObject]@{
        word = $word
        status = $status
        rejects = ($rejects | Sort-Object -Unique) -join "; "
        warnings = ($warnings | Sort-Object -Unique) -join "; "
        meaning_count = $meaningCount
        nastaliq = $nastaliq
        lead_primary = $primary
        lead_primary_roman = $primaryRoman
        lead_definition_en = $leadDefinition
    }) | Out-Null
}

$rows | Export-Csv -Path $ReportCsv -NoTypeInformation -Encoding UTF8
$rows | Where-Object { $_.status -ne "accepted" } | Export-Csv -Path $RejectedCsv -NoTypeInformation -Encoding UTF8
$accepted | Set-Content -Path $AcceptedWordsFile -Encoding UTF8

$rejectedCount = @($rows | Where-Object { $_.status -eq "rejected" }).Count
$needsReviewCount = @($rows | Where-Object { $_.status -eq "needs_review" }).Count
$warningCount = @($rows | Where-Object { $_.warnings -ne "" }).Count

Write-Host ""
Write-Host "Semantic repair QA review" -ForegroundColor Cyan
Write-Host "-------------------------" -ForegroundColor DarkGray
Write-Host "  Input words:   $($words.Count)"
Write-Host "  Accepted:      $($accepted.Count)"
Write-Host "  Rejected:      $rejectedCount"
Write-Host "  Needs review:  $needsReviewCount"
Write-Host "  With warnings: $warningCount"
Write-Host "  Accepted file: $AcceptedWordsFile"
Write-Host "  Rejected CSV:  $RejectedCsv"
Write-Host "  Report CSV:    $ReportCsv"

if ($accepted.Count -eq 0) {
    throw "No accepted repair rows after QA review."
}
