# =============================================================================
# scripts/export_azure_semantic_review_queue.ps1
#
# Exports a focused, read-only Azure semantic review queue for assistant-like
# risks. The output is a CSV for human/LLM review; this script does not mutate DB.
# =============================================================================

param(
    [int]$Limit = 100,
    [string]$OutFile = (Join-Path $PSScriptRoot ("words\processed\semantic_review_queue_{0}.csv" -f (Get-Date -Format "yyyyMMdd_HHmmss")))
)

$ErrorActionPreference = "Stop"

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
    if ($connStr -notmatch ";") { return $connStr }

    $parts = @{}
    $connStr -split ";" | ForEach-Object {
        if ($_ -match "^(.*?)=(.*)$") {
            $parts[$matches[1].Trim().ToLowerInvariant()] = $matches[2].Trim()
        }
    }

    $hostName = $parts["host"]
    $port = if ($parts.ContainsKey("port")) { $parts["port"] } else { "5432" }
    $dbName = if ($parts.ContainsKey("database")) { $parts["database"] } else { $parts["dbname"] }
    $userName = if ($parts.ContainsKey("username")) { $parts["username"] } else { $parts["user id"] }
    $password = $parts["password"]

    return "host=$hostName port=$port dbname=$dbName user=$userName password=$password sslmode=require"
}

New-Item -ItemType Directory -Path (Split-Path $OutFile -Parent) -Force | Out-Null

$sql = @"
COPY (
WITH base AS (
  SELECT word,
         word_lower,
         model,
         data->'_meta'->>'stage' AS stage,
         data->'learning'->>'difficulty' AS difficulty,
         data->'learning'->>'cefr_level' AS cefr_level,
         CASE
           WHEN data->'learning'->>'frequency_rank' ~ '^[0-9]+$'
           THEN (data->'learning'->>'frequency_rank')::int
           ELSE NULL
         END AS frequency_rank,
         data->'script_variants'->>'nastaliq' AS script_nastaliq,
         data->'script_variants'->>'roman_urdu' AS script_roman,
         lower(regexp_replace(COALESCE(data->'script_variants'->>'roman_urdu', ''), '[^a-z]', '', 'g')) AS script_roman_norm,
         CASE WHEN jsonb_typeof(data->'meanings') = 'array' THEN jsonb_array_length(data->'meanings') ELSE 0 END AS meaning_count,
         CASE WHEN jsonb_typeof(data->'meanings') = 'array' THEN data->'meanings'->0->>'pos' ELSE NULL END AS first_pos,
         CASE WHEN jsonb_typeof(data->'meanings') = 'array' THEN data->'meanings'->0->>'definition_en' ELSE NULL END AS first_definition_en,
         CASE WHEN jsonb_typeof(data->'meanings') = 'array' THEN data->'meanings'->0->'translations'->>'primary' ELSE NULL END AS primary_ur,
         CASE WHEN jsonb_typeof(data->'meanings') = 'array' THEN data->'meanings'->0->'translations'->>'primary_roman' ELSE NULL END AS primary_roman,
         CASE WHEN jsonb_typeof(data->'meanings') = 'array' THEN lower(regexp_replace(COALESCE(data->'meanings'->0->'translations'->>'primary_roman', ''), '[^a-z]', '', 'g')) ELSE '' END AS primary_roman_norm,
         CASE WHEN jsonb_typeof(data->'meanings') = 'array' THEN data->'meanings'->0->'translations'->'alternatives' ELSE NULL END AS alternatives
  FROM word_definitions
),
flags AS (
  SELECT *,
         (primary_roman_norm = word_lower) AS meaning_primary_roman_equals_word,
         (script_roman_norm = word_lower) AS script_roman_equals_word,
         CASE
           WHEN jsonb_typeof(alternatives) = 'array' THEN jsonb_array_length(alternatives) > 0
           ELSE false
         END AS has_alternatives,
         (
           COALESCE(frequency_rank, 999999) <= 5000
           OR difficulty IN ('beginner', 'intermediate')
           OR cefr_level IN ('A1', 'A2', 'B1', 'B2')
         ) AS common_or_learning_word
  FROM base
)
SELECT word,
       model,
       stage,
       difficulty,
       cefr_level,
       frequency_rank,
       meaning_count,
       script_nastaliq,
       script_roman,
       primary_ur,
       primary_roman,
       alternatives::text AS alternatives,
       first_pos,
       first_definition_en,
       '' AS review_verdict,
       '' AS review_action,
       '' AS review_notes
FROM flags
WHERE meaning_primary_roman_equals_word
  AND has_alternatives
  AND common_or_learning_word
ORDER BY COALESCE(frequency_rank, 999999), word
LIMIT $Limit
) TO STDOUT WITH CSV HEADER;
"@

$conn = Get-AzureConnectionString
$pgConn = Convert-ToPsqlConnStr $conn
$csv = $sql | docker compose exec -T postgres psql $pgConn -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) {
    throw "Failed to export semantic review queue."
}
$csv | Set-Content -Encoding UTF8 $OutFile

Write-Host "Exported semantic review queue: $OutFile" -ForegroundColor Green
