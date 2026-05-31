# =============================================================================
# scripts/audit_azure_semantic_risk.ps1
#
# Read-only semantic-risk audit for Azure word_definitions.
#
# This does not judge every Urdu translation. It flags rows that look similar to
# the "assistant" issue: the primary Urdu path appears to use an English
# transliteration, especially when alternatives contain other Urdu choices.
# =============================================================================

param(
    [int]$SampleCount = 50
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
    if ([string]::IsNullOrWhiteSpace($connStr)) { return $connStr }
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

$sql = @"
\pset pager off

DROP TABLE IF EXISTS tmp_semantic_risk_flags;

CREATE TEMP TABLE tmp_semantic_risk_flags AS
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
         lower(regexp_replace(COALESCE(data->'script_variants'->>'roman_urdu', ''), '[^a-z]', '', 'g')) AS script_roman_norm,
         data->'meanings'->0->'translations'->>'primary' AS primary_ur,
         lower(regexp_replace(COALESCE(data->'meanings'->0->'translations'->>'primary_roman', ''), '[^a-z]', '', 'g')) AS primary_roman_norm,
         data->'meanings'->0->'translations'->'alternatives' AS alternatives,
         jsonb_array_length(data->'meanings') AS meaning_count
  FROM word_definitions
),
flags AS (
  SELECT *,
         (primary_roman_norm = word_lower) AS meaning_primary_roman_equals_word,
         (script_roman_norm = word_lower) AS script_roman_equals_word,
         (primary_roman_norm = word_lower OR script_roman_norm = word_lower) AS any_primary_path_roman_equals_word,
         (jsonb_typeof(alternatives) = 'array' AND jsonb_array_length(alternatives) > 0) AS has_alternatives,
         (
           difficulty IN ('beginner', 'intermediate')
           OR cefr_level IN ('A1', 'A2', 'B1')
           OR COALESCE(frequency_rank, 999999999) <= 5000
         ) AS common_or_learning_word,
         (meaning_count = 1 AND stage = 'enriched') AS thin_enriched
  FROM base
)
SELECT *
FROM flags;

\echo '== transliteration-primary risk counts =='
SELECT COUNT(*) AS total_definitions,
       COUNT(*) FILTER (WHERE meaning_primary_roman_equals_word) AS meaning_primary_roman_equals_word,
       COUNT(*) FILTER (WHERE script_roman_equals_word) AS script_roman_equals_word,
       COUNT(*) FILTER (WHERE meaning_primary_roman_equals_word AND script_roman_equals_word) AS both_primary_paths_roman_equal_word,
       COUNT(*) FILTER (WHERE meaning_primary_roman_equals_word AND has_alternatives) AS assistant_like_with_alternatives,
       COUNT(*) FILTER (WHERE meaning_primary_roman_equals_word AND common_or_learning_word) AS common_meaning_primary_roman_equals_word,
       COUNT(*) FILTER (WHERE meaning_primary_roman_equals_word AND common_or_learning_word AND has_alternatives) AS common_assistant_like_with_alternatives,
       COUNT(*) FILTER (WHERE thin_enriched) AS thin_enriched_one_meaning
FROM tmp_semantic_risk_flags;

\echo '== risk by model/stage =='
SELECT COALESCE(model, '<null>') AS model,
       COALESCE(stage, '<missing>') AS stage,
       COUNT(*) FILTER (WHERE meaning_primary_roman_equals_word) AS meaning_primary_roman_equals_word,
       COUNT(*) FILTER (WHERE script_roman_equals_word) AS script_roman_equals_word,
       COUNT(*) FILTER (WHERE meaning_primary_roman_equals_word AND common_or_learning_word AND has_alternatives) AS common_assistant_like,
       COUNT(*) FILTER (WHERE thin_enriched) AS thin_enriched
FROM tmp_semantic_risk_flags
GROUP BY model, stage
ORDER BY common_assistant_like DESC, meaning_primary_roman_equals_word DESC, model, stage;

\echo '== highest-risk sample: common words where primary roman equals English and alternatives exist =='
SELECT word,
       model,
       stage,
       difficulty,
       cefr_level,
       frequency_rank,
       script_nastaliq,
       primary_ur,
       primary_roman_norm,
       alternatives,
       meaning_count
FROM tmp_semantic_risk_flags
WHERE meaning_primary_roman_equals_word
  AND common_or_learning_word
  AND has_alternatives
ORDER BY COALESCE(frequency_rank, 999999999), word
LIMIT $SampleCount;

\echo '== thin enriched sample =='
SELECT word,
       model,
       stage,
       difficulty,
       cefr_level,
       frequency_rank,
       script_nastaliq,
       primary_ur,
       primary_roman_norm,
       meaning_count
FROM tmp_semantic_risk_flags
WHERE thin_enriched
ORDER BY COALESCE(frequency_rank, 999999999), word
LIMIT $SampleCount;
"@

$conn = Convert-ToPsqlConnStr (Get-AzureConnectionString)
$sql | docker compose exec -T postgres psql $conn -v ON_ERROR_STOP=1
