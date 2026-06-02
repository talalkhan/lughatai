# =============================================================================
# scripts/classify_semantic_review_queue.ps1
#
# Deterministic no-AI classifier for semantic-risk queue rows.
# Splits rows into keep / repair / review so valid Urdu loanwords do not waste
# repair budget and obvious bad rows can be targeted first.
# =============================================================================

param(
    [string]$InputCsv = (Join-Path $PSScriptRoot "words\processed\semantic_review_queue_remaining_20260602.csv"),
    [string]$OutCsv = (Join-Path $PSScriptRoot "words\processed\semantic_review_queue_classified_20260602.csv"),
    [string]$SummaryFile = (Join-Path $PSScriptRoot "words\processed\semantic_review_queue_classified_20260602_summary.txt")
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

function Read-JsonArrayStrings([string]$json) {
    if ([string]::IsNullOrWhiteSpace($json) -or $json -eq "null") { return @() }
    try {
        $value = $json | ConvertFrom-Json
        return @($value | ForEach-Object { [string]$_ })
    } catch {
        return @()
    }
}

function Get-PrimaryTokens([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return @() }
    return @($value.ToLowerInvariant() -split "[\s،,;:()/\-_]+" | Where-Object { $_ -ne "" })
}

$knownGoodLoanwords = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@(
    "adapter","adaptor","aerosol","airport","album","albums","aluminium","ambulance","apartment",
    "archive","arena","auditorium","autobus","babu","bakery","barbecue","bazaar","blazer",
    "boiler","bolt","bonus","booking","booth","boycott","brigade","browser","budget","bun",
    "cable","camp","campus","canteen","carbohydrate","carton","casino","channel","channels",
    "champion","championship","chrome","circuit","circus","clone","cocktail","college",
    "commissioner","computer","computerization","copyright","coupon","cricket","cruiser",
    "currency","dashboard","database","delta","dent","director","directors","dishwasher",
    "doctor","drama","drummer","engineer","expo","factory","fashion","fashionable","fascism",
    "fiat","firewall","folder","footballer","furniture","gendarmerie","ghetto","gladiator",
    "golfing","greenhouse","grid","grids","gym","handbag","handbook","hardware","hash",
    "heater","heels","hernia","highway","hippy","hormones","hypothermia","injections",
    "interface","invoice","jet","joker","juggler","junior","juniors","kindergarten","lab",
    "label","licensing","limo","logistics","macro","marble","midtown","millionaire",
    "moderator","module","motorcar","motorist","motors","newsletter","notation",
    "notification","notifications","oasis","opiate","oven","packet","pajama","pasta",
    "passports","passwords","petticoat","photocopies","photographers","picnic","pistol",
    "policy","podium","processor","promo","pullover","ration","recorder","registration",
    "restaurant","rivet","robot","rocket","routine","samba","sausage","sensor","serial",
    "sofa","sprinkler","stadium","sultan","sweater","switchboard","tab","tanker","toast",
    "tobacco","trillion","trolley","university","vaccine","valve","villa","website",
    "websites","wicket","wickets","workbook","workshop"
) | ForEach-Object { [void]$knownGoodLoanwords.Add($_) }

$knownBadPrimaryByWord = @{
    "bored" = @("بورڈ")
    "campus" = @("کیملز")
    "coup" = @("کُوپ", "کوپ")
    "pickax" = @("پیک ایکس")
    "alcove" = @("الکوب")
    "ballad" = @("بالاد")
    "banger" = @("بنگر")
    "booth" = @("بوت")
    "fluke" = @("فلوک")
    "coupon" = @("کپرون")
    "cockroach" = @("بلیوں کی ککروچ")
    "hiccup" = @("ہک اپ")
    "invoice" = @("انVOICE")
    "inkling" = @("ایکیٹنگ")
}

$badAlternativeFragments = @(
    "نان بائیک",
    "مکسر",
    "درستہ",
    "جاپت",
    "شہزادہ",
    "نحویہ",
    "معالجہ",
    "مقید",
    "سوزوکی",
    "بہن",
    "ملتزم"
)

$goodSemanticAlternativeFragments = @(
    "کارکن","نان بائی","نانوائی","خباز","کدال","گیتی","بیزار","اکتایا","تنگ",
    "بغاوت","تختہ","اقتدار","طاقچہ","گوشہ","فوجی دستہ","دستہ","رکن","جامعہ",
    "معلومات","آلہ","نلکی","حلقہ","قاعدہ","اصول","رپورٹ","تجاویز","رائے دہندہ",
    "تربیت","مشق","سفوف","چمٹا","شیشی","ذخیرہ","معمول","رکنِ پارلیمان"
)

if (-not (Test-Path $InputCsv)) { throw "Input CSV not found: $InputCsv" }
New-Item -ItemType Directory -Path (Split-Path $OutCsv -Parent) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $SummaryFile -Parent) -Force | Out-Null

$rows = Import-Csv $InputCsv
$classified = foreach ($row in $rows) {
    $word = ([string]$row.word).Trim().ToLowerInvariant()
    $primary = [string]$row.primary_ur
    $script = [string]$row.script_nastaliq
    $primaryRoman = [string]$row.primary_roman
    $alternatives = Read-JsonArrayStrings ([string]$row.alternatives)
    $meaningCount = 0
    [void][int]::TryParse([string]$row.meaning_count, [ref]$meaningCount)
    $freq = 999999
    [void][int]::TryParse([string]$row.frequency_rank, [ref]$freq)

    $verdict = "review"
    $reason = "ambiguous_or_needs_human_review"
    $suggestedAction = "review_sample"

    $primaryNorm = Normalize-Roman $primaryRoman
    $wordNorm = Normalize-Roman $word
    $scriptHasLatin = Has-Latin $script
    $primaryHasLatin = Has-Latin $primary
    $hasUrduPrimary = Has-Urdu $primary
    $altText = ($alternatives -join " | ")

    $knownBad = $false
    if ($knownBadPrimaryByWord.ContainsKey($word)) {
        foreach ($bad in @($knownBadPrimaryByWord[$word])) {
            if ($primary.Trim() -eq $bad) { $knownBad = $true }
        }
    }

    $hasBadAlt = $false
    foreach ($fragment in $badAlternativeFragments) {
        if ($altText.Contains($fragment)) { $hasBadAlt = $true }
    }

    $hasGoodSemanticAlt = $false
    foreach ($fragment in $goodSemanticAlternativeFragments) {
        if ($altText.Contains($fragment)) { $hasGoodSemanticAlt = $true }
    }

    if (-not $hasUrduPrimary -or $scriptHasLatin -or $primaryHasLatin) {
        $verdict = "repair"
        $reason = "primary_or_script_contains_latin_or_missing_urdu"
        $suggestedAction = "repair"
    } elseif ($knownBad) {
        $verdict = "repair"
        $reason = "known_bad_primary_for_word"
        $suggestedAction = "repair"
    } elseif ($hasBadAlt) {
        $verdict = "repair"
        $reason = "contains_known_bad_alternative"
        $suggestedAction = "repair_or_cleanup_alternatives"
    } elseif ($knownGoodLoanwords.Contains($word) -and $primaryNorm -eq $wordNorm) {
        $verdict = "keep"
        $reason = "known_common_urdu_loanword"
        $suggestedAction = "mark_reviewed_keep"
    } elseif ($primaryNorm -eq $wordNorm -and $hasGoodSemanticAlt -and $meaningCount -le 2 -and $freq -le 5000) {
        $verdict = "repair"
        $reason = "loanword_primary_but_good_semantic_alternative_exists"
        $suggestedAction = "promote_semantic_alternative_or_patch"
    } elseif ($primaryNorm -eq $wordNorm -and $meaningCount -ge 3) {
        $verdict = "keep"
        $reason = "multi_sense_repair_already_present_or_loanword_acceptable"
        $suggestedAction = "mark_reviewed_keep"
    } elseif ($primaryNorm -eq $wordNorm) {
        $verdict = "review"
        $reason = "loanword_primary_not_in_keep_list"
        $suggestedAction = "review_or_add_to_keep_list"
    }

    [PSCustomObject]@{
        verdict = $verdict
        reason = $reason
        suggested_action = $suggestedAction
        word = $row.word
        model = $row.model
        stage = $row.stage
        difficulty = $row.difficulty
        cefr_level = $row.cefr_level
        frequency_rank = $row.frequency_rank
        meaning_count = $row.meaning_count
        script_nastaliq = $row.script_nastaliq
        primary_ur = $row.primary_ur
        primary_roman = $row.primary_roman
        alternatives = $row.alternatives
        first_pos = $row.first_pos
        first_definition_en = $row.first_definition_en
    }
}

$classified | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8

$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add("Semantic review queue classification") | Out-Null
$summaryLines.Add("Generated: $(Get-Date -Format o)") | Out-Null
$summaryLines.Add("Input: $InputCsv") | Out-Null
$summaryLines.Add("Output: $OutCsv") | Out-Null
$summaryLines.Add("") | Out-Null
$summaryLines.Add("== verdict counts ==") | Out-Null
$classified | Group-Object verdict | Sort-Object Name | ForEach-Object {
    $summaryLines.Add(("{0}: {1}" -f $_.Name, $_.Count)) | Out-Null
}
$summaryLines.Add("") | Out-Null
$summaryLines.Add("== reason counts ==") | Out-Null
$classified | Group-Object reason | Sort-Object Count -Descending | ForEach-Object {
    $summaryLines.Add(("{0}: {1}" -f $_.Name, $_.Count)) | Out-Null
}
$summaryLines | Set-Content -Path $SummaryFile -Encoding UTF8

Write-Host ""
Write-Host "Semantic review queue classification" -ForegroundColor Cyan
Write-Host "------------------------------------" -ForegroundColor DarkGray
Write-Host "  Input rows: $($rows.Count)"
$classified | Group-Object verdict | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0}: {1}" -f $_.Name, $_.Count)
}
Write-Host "  Output:  $OutCsv"
Write-Host "  Summary: $SummaryFile"
