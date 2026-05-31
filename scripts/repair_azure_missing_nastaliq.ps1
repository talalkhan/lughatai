# =============================================================================
# scripts/repair_azure_missing_nastaliq.ps1
#
# Production metadata/content repair for rows with a missing
# data.script_variants.nastaliq value. It fills that value from the first
# meaning's translations.primary when available, and optionally fills
# script_variants.roman_urdu from translations.primary_roman when missing.
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

$missingNastaliqWhere = "data->'script_variants'->>'nastaliq' IS NULL OR data->'script_variants'->>'nastaliq' = ''"
$repairableWhere = "($missingNastaliqWhere) AND data->'meanings'->0->'translations'->>'primary' IS NOT NULL AND data->'meanings'->0->'translations'->>'primary' <> ''"

$modeSql = if ($Apply) {
@"
\echo '== applying repair =='
WITH candidates AS (
  SELECT word_lower,
         data->'meanings'->0->'translations'->>'primary' AS primary_ur,
         data->'meanings'->0->'translations'->>'primary_roman' AS primary_roman
  FROM word_definitions
  WHERE $repairableWhere
),
updated AS (
  UPDATE word_definitions wd
  SET data = jsonb_set(
              jsonb_set(
                CASE
                  WHEN jsonb_typeof(wd.data->'script_variants') = 'object' THEN wd.data
                  ELSE jsonb_set(wd.data, '{script_variants}', '{}'::jsonb, true)
                END,
                '{script_variants,nastaliq}',
                to_jsonb(c.primary_ur),
                true
              ),
              '{script_variants,roman_urdu}',
              to_jsonb(COALESCE(NULLIF(wd.data->'script_variants'->>'roman_urdu', ''), NULLIF(c.primary_roman, ''), '')),
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
SELECT COUNT(*) AS missing_nastaliq,
       COUNT(*) FILTER (
         WHERE data->'meanings'->0->'translations'->>'primary' IS NOT NULL
           AND data->'meanings'->0->'translations'->>'primary' <> ''
       ) AS repairable_from_primary,
       COUNT(*) FILTER (
         WHERE data->'meanings'->0->'translations'->>'primary_roman' IS NOT NULL
           AND data->'meanings'->0->'translations'->>'primary_roman' <> ''
       ) AS has_primary_roman
FROM word_definitions
WHERE $missingNastaliqWhere;

SELECT word,
       model,
       data->'_meta'->>'stage' AS stage,
       data->'script_variants' AS script_variants,
       data->'meanings'->0->'translations' AS translations,
       left(data->'meanings'->0->>'definition_en', 100) AS definition_en
FROM word_definitions
WHERE $missingNastaliqWhere
ORDER BY model, stage, word
LIMIT 40;
"@
}

$sql = @"
\pset pager off

\echo '== before =='
SELECT COUNT(*) AS total_definitions,
       COUNT(*) FILTER (WHERE $missingNastaliqWhere) AS missing_nastaliq
FROM word_definitions;

$modeSql

\echo '== after =='
SELECT COUNT(*) AS total_definitions,
       COUNT(*) FILTER (WHERE $missingNastaliqWhere) AS missing_nastaliq
FROM word_definitions;
"@

$conn = Convert-ToPsqlConnStr (Get-AzureConnectionString)
$sql | docker compose exec -T postgres psql $conn -v ON_ERROR_STOP=1
