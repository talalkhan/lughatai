# =============================================================================
# scripts/quarantine_azure_word_mismatches.ps1
#
# Production cleanup for rows where word_definitions.word_lower disagrees with
# the top-level JSON data.word. These rows can show the wrong definition under a
# word URL, so they are quarantined before deletion from word_definitions.
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

$mismatchWhere = "data ? 'word' AND lower(data->>'word') <> word_lower"

$modeSql = if ($Apply) {
@"
\echo '== applying quarantine/delete =='
CREATE TABLE IF NOT EXISTS word_mismatch_quarantine (
    id integer PRIMARY KEY,
    word text NOT NULL,
    word_lower text NOT NULL,
    json_word text,
    data jsonb NOT NULL,
    lookup_count integer NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    model varchar(100),
    quarantined_at timestamptz NOT NULL DEFAULT now(),
    reason text NOT NULL
);

WITH candidates AS (
  SELECT id, word, word_lower, data->>'word' AS json_word, data, lookup_count, created_at, updated_at, model
  FROM word_definitions
  WHERE $mismatchWhere
),
quarantined AS (
  INSERT INTO word_mismatch_quarantine (
      id, word, word_lower, json_word, data, lookup_count, created_at, updated_at, model, reason
  )
  SELECT id, word, word_lower, json_word, data, lookup_count, created_at, updated_at, model,
         'word_definitions.word_lower does not match data.word'
  FROM candidates
  ON CONFLICT (id) DO UPDATE
  SET word = EXCLUDED.word,
      word_lower = EXCLUDED.word_lower,
      json_word = EXCLUDED.json_word,
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
WHERE $mismatchWhere;

SELECT word,
       data->>'word' AS json_word,
       model,
       data->'_meta'->>'stage' AS stage,
       left(data->'meanings'->0->>'definition_en', 120) AS definition_en
FROM word_definitions
WHERE $mismatchWhere
ORDER BY word
LIMIT 50;
"@
}

$sql = @"
\pset pager off

\echo '== before =='
SELECT COUNT(*) AS total_definitions,
       COUNT(*) FILTER (WHERE $mismatchWhere) AS top_word_mismatches
FROM word_definitions;

$modeSql

\echo '== after =='
SELECT COUNT(*) AS total_definitions,
       COUNT(*) FILTER (WHERE $mismatchWhere) AS top_word_mismatches
FROM word_definitions;

\echo '== quarantine table =='
SELECT to_regclass('public.word_mismatch_quarantine') AS quarantine_table;
"@

$conn = Convert-ToPsqlConnStr (Get-AzureConnectionString)
$sql | docker compose exec -T postgres psql $conn -v ON_ERROR_STOP=1
