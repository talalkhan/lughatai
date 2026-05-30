# =============================================================================
# scripts/audit_azure_word_definitions.ps1
#
# Read-only production audit for Azure word_definitions quality/counts.
# =============================================================================

param(
    [int]$SampleCount = 40
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

$conn = Convert-ToPsqlConnStr (Get-AzureConnectionString)

$sql = @"
\pset pager off

\echo '== totals =='
SELECT COUNT(*) AS total_definitions,
       COUNT(*) FILTER (WHERE model = 'gpt-4o-mini-batch') AS openai_batch_definitions,
       COUNT(*) FILTER (WHERE data->'_meta'->>'stage' = 'core') AS core_stage_definitions,
       COUNT(*) FILTER (WHERE data->'_meta'->>'stage' IS NULL) AS missing_stage_definitions
FROM word_definitions;

\echo '== by model =='
SELECT COALESCE(model, '<null>') AS model, COUNT(*) AS count
FROM word_definitions
GROUP BY model
ORDER BY count DESC, model;

\echo '== by stage =='
SELECT COALESCE(data->'_meta'->>'stage', '<missing>') AS stage, COUNT(*) AS count
FROM word_definitions
GROUP BY COALESCE(data->'_meta'->>'stage', '<missing>')
ORDER BY count DESC, stage;

\echo '== json health =='
SELECT COUNT(*) FILTER (WHERE data ? 'word') AS has_word,
       COUNT(*) FILTER (WHERE data ? 'meanings') AS has_meanings,
       COUNT(*) FILTER (WHERE jsonb_typeof(data->'meanings') = 'array' AND jsonb_array_length(data->'meanings') > 0) AS nonempty_meanings,
       COUNT(*) FILTER (WHERE data ? 'script_variants') AS has_script_variants,
       COUNT(*) FILTER (WHERE data->'script_variants'->>'nastaliq' IS NOT NULL AND data->'script_variants'->>'nastaliq' <> '') AS has_nastaliq,
       COUNT(*) FILTER (WHERE lower(data->>'word') <> word_lower) AS top_word_mismatches
FROM word_definitions;

\echo '== recent batch sample =='
SELECT word,
       data->'_meta'->>'stage' AS stage,
       data->'script_variants'->>'nastaliq' AS nastaliq,
       left(data->'meanings'->0->>'definition_en', 120) AS definition_en,
       left(data->'meanings'->0->'translations'->>'primary', 80) AS primary_ur
FROM word_definitions
WHERE model = 'gpt-4o-mini-batch'
ORDER BY random()
LIMIT $SampleCount;

\echo '== top word mismatches by model/stage =='
SELECT COALESCE(model, '<null>') AS model,
       COALESCE(data->'_meta'->>'stage', '<missing>') AS stage,
       COUNT(*) AS mismatches
FROM word_definitions
WHERE lower(data->>'word') <> word_lower
GROUP BY model, COALESCE(data->'_meta'->>'stage', '<missing>')
ORDER BY mismatches DESC, model, stage;

\echo '== mismatch sample =='
SELECT word,
       data->>'word' AS json_word,
       model,
       COALESCE(data->'_meta'->>'stage', '<missing>') AS stage,
       left(data->'meanings'->0->>'definition_en', 120) AS definition_en
FROM word_definitions
WHERE lower(data->>'word') <> word_lower
ORDER BY updated_at DESC NULLS LAST, word
LIMIT $SampleCount;

\echo '== missing/empty meanings by model/stage =='
SELECT COALESCE(model, '<null>') AS model,
       COALESCE(data->'_meta'->>'stage', '<missing>') AS stage,
       COUNT(*) AS bad_meanings
FROM word_definitions
WHERE NOT (jsonb_typeof(data->'meanings') = 'array' AND jsonb_array_length(data->'meanings') > 0)
GROUP BY model, COALESCE(data->'_meta'->>'stage', '<missing>')
ORDER BY bad_meanings DESC, model, stage;

\echo '== missing nastaliq by model/stage =='
SELECT COALESCE(model, '<null>') AS model,
       COALESCE(data->'_meta'->>'stage', '<missing>') AS stage,
       COUNT(*) AS missing_nastaliq
FROM word_definitions
WHERE data->'script_variants'->>'nastaliq' IS NULL
   OR data->'script_variants'->>'nastaliq' = ''
GROUP BY model, COALESCE(data->'_meta'->>'stage', '<missing>')
ORDER BY missing_nastaliq DESC, model, stage;

\echo '== missing stage inferred by enrichment fields =='
WITH missing AS (
  SELECT word, model, data,
         (
           (data ? 'etymology' AND data->'etymology' IS NOT NULL AND data->'etymology' <> 'null'::jsonb)
           OR (data ? 'memory_tip' AND data->'memory_tip' IS NOT NULL AND data->'memory_tip' <> 'null'::jsonb)
           OR (data ? 'urdu_poetry' AND data->'urdu_poetry' IS NOT NULL AND data->'urdu_poetry' <> 'null'::jsonb)
           OR (data ? 'urdu_proverb' AND data->'urdu_proverb' IS NOT NULL AND data->'urdu_proverb' <> 'null'::jsonb)
           OR (data ? 'islamic_reference' AND data->'islamic_reference' IS NOT NULL AND data->'islamic_reference' <> 'null'::jsonb)
           OR (jsonb_typeof(data->'word_family') = 'array' AND jsonb_array_length(data->'word_family') > 0)
           OR (jsonb_typeof(data->'related_words'->'see_also') = 'array' AND jsonb_array_length(data->'related_words'->'see_also') > 0)
           OR (jsonb_typeof(data->'related_words'->'thematic_group') = 'array' AND jsonb_array_length(data->'related_words'->'thematic_group') > 0)
         ) AS has_enrichment
  FROM word_definitions
  WHERE data->'_meta'->>'stage' IS NULL
)
SELECT CASE WHEN has_enrichment THEN 'looks_enriched' ELSE 'looks_core_or_unknown' END AS inferred_stage,
       COUNT(*) AS count
FROM missing
GROUP BY has_enrichment
ORDER BY inferred_stage;

\echo '== missing stage inferred by model =='
WITH missing AS (
  SELECT model,
         (
           (data ? 'etymology' AND data->'etymology' IS NOT NULL AND data->'etymology' <> 'null'::jsonb)
           OR (data ? 'memory_tip' AND data->'memory_tip' IS NOT NULL AND data->'memory_tip' <> 'null'::jsonb)
           OR (data ? 'urdu_poetry' AND data->'urdu_poetry' IS NOT NULL AND data->'urdu_poetry' <> 'null'::jsonb)
           OR (data ? 'urdu_proverb' AND data->'urdu_proverb' IS NOT NULL AND data->'urdu_proverb' <> 'null'::jsonb)
           OR (data ? 'islamic_reference' AND data->'islamic_reference' IS NOT NULL AND data->'islamic_reference' <> 'null'::jsonb)
           OR (jsonb_typeof(data->'word_family') = 'array' AND jsonb_array_length(data->'word_family') > 0)
           OR (jsonb_typeof(data->'related_words'->'see_also') = 'array' AND jsonb_array_length(data->'related_words'->'see_also') > 0)
           OR (jsonb_typeof(data->'related_words'->'thematic_group') = 'array' AND jsonb_array_length(data->'related_words'->'thematic_group') > 0)
         ) AS has_enrichment
  FROM word_definitions
  WHERE data->'_meta'->>'stage' IS NULL
)
SELECT COALESCE(model, '<null>') AS model,
       CASE WHEN has_enrichment THEN 'looks_enriched' ELSE 'looks_core_or_unknown' END AS inferred_stage,
       COUNT(*) AS count
FROM missing
GROUP BY model, has_enrichment
ORDER BY count DESC, model;

\echo '== missing stage sample =='
WITH missing AS (
  SELECT word, model, data,
         (
           (data ? 'etymology' AND data->'etymology' IS NOT NULL AND data->'etymology' <> 'null'::jsonb)
           OR (data ? 'memory_tip' AND data->'memory_tip' IS NOT NULL AND data->'memory_tip' <> 'null'::jsonb)
           OR (data ? 'urdu_poetry' AND data->'urdu_poetry' IS NOT NULL AND data->'urdu_poetry' <> 'null'::jsonb)
           OR (data ? 'urdu_proverb' AND data->'urdu_proverb' IS NOT NULL AND data->'urdu_proverb' <> 'null'::jsonb)
           OR (data ? 'islamic_reference' AND data->'islamic_reference' IS NOT NULL AND data->'islamic_reference' <> 'null'::jsonb)
           OR (jsonb_typeof(data->'word_family') = 'array' AND jsonb_array_length(data->'word_family') > 0)
           OR (jsonb_typeof(data->'related_words'->'see_also') = 'array' AND jsonb_array_length(data->'related_words'->'see_also') > 0)
           OR (jsonb_typeof(data->'related_words'->'thematic_group') = 'array' AND jsonb_array_length(data->'related_words'->'thematic_group') > 0)
         ) AS has_enrichment
  FROM word_definitions
  WHERE data->'_meta'->>'stage' IS NULL
)
SELECT word,
       model,
       CASE WHEN has_enrichment THEN 'looks_enriched' ELSE 'looks_core_or_unknown' END AS inferred_stage,
       (data ? 'etymology' AND data->'etymology' IS NOT NULL AND data->'etymology' <> 'null'::jsonb) AS has_etymology,
       (data ? 'memory_tip' AND data->'memory_tip' IS NOT NULL AND data->'memory_tip' <> 'null'::jsonb) AS has_memory_tip,
       (data ? 'urdu_poetry' AND data->'urdu_poetry' IS NOT NULL AND data->'urdu_poetry' <> 'null'::jsonb) AS has_poetry,
       left(data->'meanings'->0->>'definition_en', 120) AS definition_en
FROM missing
ORDER BY random()
LIMIT $SampleCount;
"@

$sql | docker compose exec -T postgres psql $conn -v ON_ERROR_STOP=1
