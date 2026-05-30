# =============================================================================
# scripts/build_missing_generation_candidates.ps1
#
# Compares local tier candidate files against production Azure word_definitions
# and writes missing candidate lists for the next OpenAI Batch run.
#
# This script does NOT write to production. It creates temp tables only.
# =============================================================================

param(
    [string]$FullCandidates = (Join-Path $PSScriptRoot "words\processed\tier_full_candidates.txt"),
    [string]$CoreCandidates = (Join-Path $PSScriptRoot "words\processed\tier_core_candidates.txt"),
    [string]$OutputDir = (Join-Path $PSScriptRoot "words\processed")
)

$ErrorActionPreference = "Stop"

function Write-H([string]$title) {
    Write-Host ""
    Write-Host $title -ForegroundColor Cyan
    Write-Host ("-" * $title.Length) -ForegroundColor DarkGray
}

function Get-AzureConnectionString {
    $conn = & 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd' webapp config appsettings list `
        --resource-group lughatai-beta-rg `
        --name lughatai-beta-api `
        --query "[?name=='ConnectionStrings__Default'].value | [0]" `
        -o tsv

    if ([string]::IsNullOrWhiteSpace($conn)) {
        throw "Could not read production database connection string from App Service settings."
    }

    return $conn
}

function Convert-ToPsqlConnStr([string]$connStr) {
    if ([string]::IsNullOrWhiteSpace($connStr)) { return $connStr }
    if ($connStr -notmatch ";") { return $connStr }

    $parts = @{}
    $connStr -split ";" | ForEach-Object {
        if ($_ -match "^(.*?)=(.*)$") {
            $parts[$matches[1].Trim().ToLowerInvariant()] = $matches[2].Trim()
        }
    }

    return "host=$($parts['host']) port=$($parts['port']) dbname=$($parts['database']) user=$($parts['username']) password=$($parts['password']) sslmode=require"
}

function Invoke-AzurePsql([string]$connStr, [string]$sql) {
    $sql | docker compose exec -T postgres psql $connStr -v ON_ERROR_STOP=1 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Azure psql failed." }
}

function Export-MissingCandidates {
    param(
        [Parameter(Mandatory)][string]$CandidateFile,
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][string]$ConnStr
    )

    if (-not (Test-Path $CandidateFile)) {
        throw "Candidate file not found: $CandidateFile"
    }

    $localTemp = Join-Path $env:TEMP ("lughatai_${Mode}_candidates_" + [Guid]::NewGuid().ToString("N") + ".txt")
    $containerCandidates = "/tmp/lughatai_${Mode}_candidates_$([Guid]::NewGuid().ToString('N')).txt"
    $containerMissing = "/tmp/lughatai_${Mode}_missing_$([Guid]::NewGuid().ToString('N')).txt"
    $outputFile = Join-Path $OutputDir "missing_${Mode}_candidates.txt"

    try {
        Get-Content $CandidateFile -Encoding UTF8 |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { $_ -match '^[a-z]{3,64}$' } |
            Sort-Object -Unique |
            Set-Content $localTemp -Encoding ascii

        docker compose cp $localTemp "postgres:$containerCandidates" | Out-Null

        $sql = @"
DROP TABLE IF EXISTS tmp_candidates;
CREATE TEMP TABLE tmp_candidates(word text PRIMARY KEY);
\copy tmp_candidates(word) FROM '$containerCandidates'
DROP TABLE IF EXISTS tmp_missing_candidates;
CREATE TEMP TABLE tmp_missing_candidates AS
SELECT c.word
FROM tmp_candidates c
LEFT JOIN word_definitions wd ON wd.word_lower = c.word
WHERE wd.word_lower IS NULL
ORDER BY c.word;
\copy tmp_missing_candidates(word) TO '$containerMissing'
SELECT COUNT(1) AS candidate_words,
       COUNT(wd.word_lower) AS already_defined,
       COUNT(1) - COUNT(wd.word_lower) AS missing_words
FROM tmp_candidates c
LEFT JOIN word_definitions wd ON wd.word_lower = c.word;
"@

        Invoke-AzurePsql $ConnStr $sql | Write-Host
        docker compose cp "postgres:$containerMissing" $outputFile | Out-Null

        $missingCount = (Get-Content $outputFile | Measure-Object -Line).Lines
        Write-Host "  $Mode missing candidates: $missingCount -> $outputFile" -ForegroundColor Green
    }
    finally {
        if (Test-Path $localTemp) { Remove-Item -LiteralPath $localTemp -Force }
    }
}

Write-H "Building missing generation candidates"
$connStr = Convert-ToPsqlConnStr (Get-AzureConnectionString)
Export-MissingCandidates -CandidateFile $FullCandidates -Mode "full" -ConnStr $connStr
Export-MissingCandidates -CandidateFile $CoreCandidates -Mode "core" -ConnStr $connStr

Write-H "Done"
Write-Host "  Review scripts\words\processed\missing_full_candidates.txt and missing_core_candidates.txt before queueing." -ForegroundColor White
