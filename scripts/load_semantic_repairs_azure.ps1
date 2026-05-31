# =============================================================================
# scripts/load_semantic_repairs_azure.ps1
#
# Loads reviewed semantic repair JSON files into Azure word_definitions.
# Creates a backup table copy of every row before replacement.
# =============================================================================

param(
    [string]$WordsFile = (Join-Path $PSScriptRoot "words\semantic_regeneration_seed.txt"),
    [string]$InputDir = (Join-Path $PSScriptRoot "words\processed\semantic_canary"),
    [string]$Model = "gpt-5.5",
    [string]$GeneratedBy = "openai",
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

function Escape-SqlLiteral([string]$value) {
    return $value.Replace("'", "''")
}

function Stamp-RepairJson([string]$path, [string]$word, [string]$model, [string]$generatedBy) {
    $node = [System.Text.Json.Nodes.JsonNode]::Parse([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8))
    if ($node -isnot [System.Text.Json.Nodes.JsonObject]) { throw "Expected JSON object in $path" }

    $obj = $node.AsObject()
    $jsonWord = [string]$obj["word"].GetValue[string]()
    if ($jsonWord.Trim().ToLowerInvariant() -ne $word.Trim().ToLowerInvariant()) {
        throw "JSON word '$jsonWord' does not match expected '$word' in $path"
    }

    $meanings = $obj["meanings"]
    if ($null -eq $meanings -or $meanings -isnot [System.Text.Json.Nodes.JsonArray] -or $meanings.AsArray().Count -eq 0) {
        throw "No meanings array in $path"
    }

    $lead = $meanings.AsArray()[0]
    $translations = $lead["translations"]
    if ($null -eq $translations) { throw "Lead meaning has no translations in $path" }
    $primary = [string]$translations["primary"].GetValue[string]()
    $primaryRoman = [string]$translations["primary_roman"].GetValue[string]()
    if ([string]::IsNullOrWhiteSpace($primary) -or [string]::IsNullOrWhiteSpace($primaryRoman)) {
        throw "Lead primary translation is blank in $path"
    }

    $script = $obj["script_variants"]
    if ($null -eq $script) {
        $scriptObj = [System.Text.Json.Nodes.JsonObject]::new()
        $obj.Add("script_variants", $scriptObj)
    } else {
        $scriptObj = $script.AsObject()
    }
    $scriptObj.Remove("nastaliq") | Out-Null
    $scriptObj.Add("nastaliq", [System.Text.Json.Nodes.JsonValue]::Create($primary.Trim()))
    $scriptObj.Remove("roman_urdu") | Out-Null
    $scriptObj.Add("roman_urdu", [System.Text.Json.Nodes.JsonValue]::Create($primaryRoman.Trim()))
    if (-not $scriptObj.ContainsKey("devanagari")) { $scriptObj.Add("devanagari", $null) }

    $meta = $obj["_meta"]
    if ($null -eq $meta) {
        $metaObj = [System.Text.Json.Nodes.JsonObject]::new()
        $obj.Add("_meta", $metaObj)
    } else {
        $metaObj = $meta.AsObject()
    }
    foreach ($key in @("generated_by", "generated_at", "model", "stage", "version", "reviewed", "semantic_repair")) {
        $metaObj.Remove($key) | Out-Null
    }
    $metaObj.Add("generated_by", [System.Text.Json.Nodes.JsonValue]::Create($generatedBy))
    $metaObj.Add("generated_at", [System.Text.Json.Nodes.JsonValue]::Create([DateTime]::UtcNow.ToString("O")))
    $metaObj.Add("model", [System.Text.Json.Nodes.JsonValue]::Create($model))
    $metaObj.Add("stage", [System.Text.Json.Nodes.JsonValue]::Create("enriched"))
    $metaObj.Add("version", [System.Text.Json.Nodes.JsonValue]::Create("1.0"))
    $metaObj.Add("reviewed", [System.Text.Json.Nodes.JsonValue]::Create($true))
    $metaObj.Add("semantic_repair", [System.Text.Json.Nodes.JsonValue]::Create($true))

    return $node.ToJsonString([System.Text.Json.JsonSerializerOptions]::new())
}

if (-not (Test-Path $WordsFile)) { throw "Words file not found: $WordsFile" }
if (-not (Test-Path $InputDir)) { throw "Input dir not found: $InputDir" }

$words = Get-Content $WordsFile -Encoding UTF8 |
    ForEach-Object { $_.Trim().ToLowerInvariant() } |
    Where-Object { $_ -ne "" -and -not $_.StartsWith("#") }

if ($words.Count -eq 0) { throw "No words found in $WordsFile" }

$items = @()
foreach ($word in $words) {
    $path = Join-Path $InputDir "$word.json"
    if (-not (Test-Path $path)) { throw "Missing repair JSON: $path" }
    $json = Stamp-RepairJson -path $path -word $word -model $Model -generatedBy $GeneratedBy
    $items += [PSCustomObject]@{ Word = $word; Json = $json }
}

Write-Host ""
Write-Host "Semantic repair load" -ForegroundColor Cyan
Write-Host "--------------------" -ForegroundColor DarkGray
Write-Host "  Rows:   $($items.Count)"
Write-Host "  Model:  $Model"
Write-Host "  Target: Azure production database"
Write-Host "  Mode:   $(if ($Apply) { 'APPLY' } else { 'DRY RUN' })"

$runId = [Guid]::NewGuid().ToString()
$wordListSql = ($items | ForEach-Object { "'" + (Escape-SqlLiteral $_.Word) + "'" }) -join ","

$sql = [System.Text.StringBuilder]::new()
$sql.AppendLine("BEGIN;") | Out-Null
$sql.AppendLine("CREATE TABLE IF NOT EXISTS semantic_repair_backup (id bigserial PRIMARY KEY, run_id uuid NOT NULL, word text NOT NULL, backed_up_at timestamptz NOT NULL DEFAULT now(), old_model text, old_data jsonb NOT NULL, new_model text NOT NULL, note text);") | Out-Null
$sql.AppendLine("SELECT word, model, data->'script_variants'->>'nastaliq' AS old_nastaliq, jsonb_array_length(data->'meanings') AS old_meanings FROM word_definitions WHERE word_lower IN ($wordListSql) ORDER BY word_lower;") | Out-Null

if ($Apply) {
    foreach ($item in $items) {
        $wordEsc = Escape-SqlLiteral $item.Word
        $jsonEsc = Escape-SqlLiteral $item.Json
        $modelEsc = Escape-SqlLiteral $Model
        $sql.AppendLine("INSERT INTO semantic_repair_backup (run_id, word, old_model, old_data, new_model, note) SELECT '$runId'::uuid, word, model, data, '$modelEsc', 'gpt semantic repair canary accepted' FROM word_definitions WHERE word_lower = '$wordEsc';") | Out-Null
        $sql.AppendLine("UPDATE word_definitions SET data = '$jsonEsc'::jsonb, model = '$modelEsc', updated_at = now() WHERE word_lower = '$wordEsc';") | Out-Null
    }
    $sql.AppendLine("SELECT word, model, data->'_meta'->>'model' AS meta_model, data->'script_variants'->>'nastaliq' AS new_nastaliq, data->'meanings'->0->'translations'->>'primary' AS primary, jsonb_array_length(data->'meanings') AS meanings FROM word_definitions WHERE word_lower IN ($wordListSql) ORDER BY word_lower;") | Out-Null
} else {
    $sql.AppendLine("ROLLBACK;") | Out-Null
}

if ($Apply) {
    $sql.AppendLine("COMMIT;") | Out-Null
}

$conn = Convert-ToPsqlConnStr (Get-AzureConnectionString)
$output = $sql.ToString() | docker compose exec -T postgres psql $conn -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) { throw "Azure semantic repair load failed." }

Write-Host $output
if ($Apply) {
    Write-Host "Applied semantic repairs. Backup run_id: $runId" -ForegroundColor Green
} else {
    Write-Host "Dry run complete. Re-run with -Apply to update Azure." -ForegroundColor Yellow
}
