# =============================================================================
# scripts/stamp_azure_missing_stage_enriched.ps1
#
# Production metadata repair: stamp Azure word_definitions rows as enriched when
# _meta.stage is missing but enrichment-only fields are populated.
#
# This does not alter dictionary meanings/translations. It only sets:
#   data._meta.stage = "enriched"
# =============================================================================

param(
    [switch]$Apply
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

$whereLooksEnriched = @"
data->'_meta'->>'stage' IS NULL
AND (
  (data ? 'etymology' AND data->'etymology' IS NOT NULL AND data->'etymology' <> 'null'::jsonb)
  OR (data ? 'memory_tip' AND data->'memory_tip' IS NOT NULL AND data->'memory_tip' <> 'null'::jsonb)
  OR (data ? 'urdu_poetry' AND data->'urdu_poetry' IS NOT NULL AND data->'urdu_poetry' <> 'null'::jsonb)
  OR (data ? 'urdu_proverb' AND data->'urdu_proverb' IS NOT NULL AND data->'urdu_proverb' <> 'null'::jsonb)
  OR (data ? 'islamic_reference' AND data->'islamic_reference' IS NOT NULL AND data->'islamic_reference' <> 'null'::jsonb)
  OR (jsonb_typeof(data->'word_family') = 'array' AND jsonb_array_length(data->'word_family') > 0)
  OR (jsonb_typeof(data->'related_words'->'see_also') = 'array' AND jsonb_array_length(data->'related_words'->'see_also') > 0)
  OR (jsonb_typeof(data->'related_words'->'thematic_group') = 'array' AND jsonb_array_length(data->'related_words'->'thematic_group') > 0)
)
"@

$modeSql = if ($Apply) {
@"
\echo '== applying metadata repair =='
WITH candidates AS (
  SELECT word_lower
  FROM word_definitions
  WHERE $whereLooksEnriched
),
updated AS (
  UPDATE word_definitions wd
  SET data = jsonb_set(
              CASE
                WHEN jsonb_typeof(wd.data->'_meta') = 'object' THEN wd.data
                ELSE jsonb_set(wd.data, '{_meta}', '{}'::jsonb, true)
              END,
              '{_meta,stage}',
              '"enriched"'::jsonb,
              true
            ),
      updated_at = now()
  FROM candidates c
  WHERE wd.word_lower = c.word_lower
  RETURNING wd.word_lower
)
SELECT COUNT(*) AS updated_rows FROM updated;
"@
} else {
@"
\echo '== dry run only =='
SELECT COUNT(*) AS rows_that_would_be_updated
FROM word_definitions
WHERE $whereLooksEnriched;
"@
}

$sql = @"
\pset pager off

\echo '== before =='
SELECT COUNT(*) AS total_definitions,
       COUNT(*) FILTER (WHERE data->'_meta'->>'stage' IS NULL) AS missing_stage,
       COUNT(*) FILTER (WHERE data->'_meta'->>'stage' = 'enriched') AS enriched_stage,
       COUNT(*) FILTER (WHERE data->'_meta'->>'stage' = 'core') AS core_stage
FROM word_definitions;

$modeSql

\echo '== after =='
SELECT COUNT(*) AS total_definitions,
       COUNT(*) FILTER (WHERE data->'_meta'->>'stage' IS NULL) AS missing_stage,
       COUNT(*) FILTER (WHERE data->'_meta'->>'stage' = 'enriched') AS enriched_stage,
       COUNT(*) FILTER (WHERE data->'_meta'->>'stage' = 'core') AS core_stage
FROM word_definitions;
"@

$conn = Convert-ToPsqlConnStr (Get-AzureConnectionString)
$sql | docker compose exec -T postgres psql $conn -v ON_ERROR_STOP=1
