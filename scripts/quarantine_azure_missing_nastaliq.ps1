# =============================================================================
# scripts/quarantine_azure_missing_nastaliq.ps1
#
# Production cleanup for rows whose primary script_variants.nastaliq is still
# missing after repair attempts. These rows have meanings but no usable primary
# Urdu head translation, so they are quarantined before deletion.
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

$modeSql = if ($Apply) {
@"
\echo '== applying quarantine/delete =='
CREATE TABLE IF NOT EXISTS missing_nastaliq_quarantine (
    id integer PRIMARY KEY,
    word text NOT NULL,
    word_lower text NOT NULL,
    data jsonb NOT NULL,
    lookup_count integer NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    model varchar(100),
    quarantined_at timestamptz NOT NULL DEFAULT now(),
    reason text NOT NULL
);

WITH candidates AS (
  SELECT id, word, word_lower, data, lookup_count, created_at, updated_at, model
  FROM word_definitions
  WHERE $missingNastaliqWhere
),
quarantined AS (
  INSERT INTO missing_nastaliq_quarantine (
      id, word, word_lower, data, lookup_count, created_at, updated_at, model, reason
  )
  SELECT id, word, word_lower, data, lookup_count, created_at, updated_at, model,
         'data.script_variants.nastaliq is missing after repair attempt'
  FROM candidates
  ON CONFLICT (id) DO UPDATE
  SET word = EXCLUDED.word,
      word_lower = EXCLUDED.word_lower,
      data = EXCLUDED.data,
      lookup_count = EXCLUDED.lookup_count,
      created_at = EXCLUDED.created_at,
      updated_at = EXCLUDED.updated_at,
      model = EXCLUDED.model,
      quarantined_at = now(),
      reason = EXCLUDED.reason
  RETURNING id
),
deleted AS (
  DELETE FROM word_definitions wd
  USING quarantined q
  WHERE wd.id = q.id
  RETURNING wd.id
)
SELECT (SELECT COUNT(*) FROM quarantined) AS quarantined_rows,
       (SELECT COUNT(*) FROM deleted) AS deleted_rows;
"@
} else {
@"
\echo '== dry run only =='
SELECT COUNT(*) AS rows_that_would_be_quarantined
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
LIMIT 50;
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

\echo '== quarantine table =='
SELECT to_regclass('public.missing_nastaliq_quarantine') AS quarantine_table;
"@

$conn = Convert-ToPsqlConnStr (Get-AzureConnectionString)
$sql | docker compose exec -T postgres psql $conn -v ON_ERROR_STOP=1
