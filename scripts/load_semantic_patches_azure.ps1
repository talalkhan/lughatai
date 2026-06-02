# =============================================================================
# scripts/load_semantic_patches_azure.ps1
#
# Loads reviewed semantic repair patches into Azure. Only updates
# script_variants and meanings; preserves the rest of the existing JSON row.
# =============================================================================

param(
    [string]$WordsFile = (Join-Path $PSScriptRoot "words\processed\gemini_semantic_patches_reviewed_accepted.txt"),
    [string]$PatchDir = (Join-Path $PSScriptRoot "words\processed\gemini_semantic_patches"),
    [string]$Model = "gemini-2.5-flash-lite",
    [string]$GeneratedBy = "google",
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

function Get-PatchItem([string]$path, [string]$word) {
    $patch = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (([string]$patch.word).Trim().ToLowerInvariant() -ne $word) {
        throw "Patch word mismatch in $path"
    }

    $script = @{
        nastaliq = [string]$patch.script_variants.nastaliq
        roman_urdu = [string]$patch.script_variants.roman_urdu
        devanagari = $null
    }

    $meanings = @($patch.meanings)
    if ($meanings.Count -eq 0) { throw "Patch has no meanings: $path" }

    return [PSCustomObject]@{
        Word = $word
        ScriptJson = ($script | ConvertTo-Json -Depth 20 -Compress)
        MeaningsJson = ($meanings | ConvertTo-Json -Depth 100 -Compress)
    }
}

if (-not (Test-Path $WordsFile)) { throw "Words file not found: $WordsFile" }
if (-not (Test-Path $PatchDir)) { throw "Patch dir not found: $PatchDir" }

$words = Get-Content $WordsFile -Encoding UTF8 |
    ForEach-Object { $_.Trim().ToLowerInvariant() } |
    Where-Object { $_ -ne "" -and -not $_.StartsWith("#") } |
    Sort-Object -Unique

if ($words.Count -eq 0) { throw "No words found in $WordsFile" }

$items = @()
foreach ($word in $words) {
    $path = Join-Path $PatchDir "$word.patch.json"
    if (-not (Test-Path $path)) { throw "Missing patch JSON: $path" }
    $items += Get-PatchItem -path $path -word $word
}

Write-Host ""
Write-Host "Semantic patch load" -ForegroundColor Cyan
Write-Host "-------------------" -ForegroundColor DarkGray
Write-Host "  Rows:   $($items.Count)"
Write-Host "  Model:  $Model"
Write-Host "  Target: Azure production database"
Write-Host "  Mode:   $(if ($Apply) { 'APPLY' } else { 'DRY RUN' })"

$runId = [Guid]::NewGuid().ToString()
$wordListSql = ($items | ForEach-Object { "'" + (Escape-SqlLiteral $_.Word) + "'" }) -join ","

$sql = [System.Text.StringBuilder]::new()
$sql.AppendLine("BEGIN;") | Out-Null
$sql.AppendLine("CREATE TABLE IF NOT EXISTS semantic_patch_backup (id bigserial PRIMARY KEY, run_id uuid NOT NULL, word text NOT NULL, backed_up_at timestamptz NOT NULL DEFAULT now(), old_model text, old_data jsonb NOT NULL, new_model text NOT NULL, note text);") | Out-Null
$sql.AppendLine("SELECT word, model, data->'script_variants'->>'nastaliq' AS old_nastaliq, jsonb_array_length(data->'meanings') AS old_meanings FROM word_definitions WHERE word_lower IN ($wordListSql) ORDER BY word_lower;") | Out-Null

if ($Apply) {
    foreach ($item in $items) {
        $wordEsc = Escape-SqlLiteral $item.Word
        $scriptEsc = Escape-SqlLiteral $item.ScriptJson
        $meaningsEsc = Escape-SqlLiteral $item.MeaningsJson
        $modelEsc = Escape-SqlLiteral $Model
        $generatedByEsc = Escape-SqlLiteral $GeneratedBy
        $now = [DateTime]::UtcNow.ToString("O")
        $nowEsc = Escape-SqlLiteral $now

        $sql.AppendLine("INSERT INTO semantic_patch_backup (run_id, word, old_model, old_data, new_model, note) SELECT '$runId'::uuid, word, model, data, '$modelEsc', 'gemini semantic patch accepted' FROM word_definitions WHERE word_lower = '$wordEsc';") | Out-Null
        $sql.AppendLine("UPDATE word_definitions SET data = jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(data, '{script_variants}', '$scriptEsc'::jsonb, true), '{meanings}', '$meaningsEsc'::jsonb, true), '{_meta,generated_by}', to_jsonb('$generatedByEsc'::text), true), '{_meta,generated_at}', to_jsonb('$nowEsc'::text), true), '{_meta,model}', to_jsonb('$modelEsc'::text), true), '{_meta,semantic_patch}', 'true'::jsonb, true), model = '$modelEsc', updated_at = now() WHERE word_lower = '$wordEsc';") | Out-Null
    }
    $sql.AppendLine("SELECT word, model, data->'_meta'->>'model' AS meta_model, data->'script_variants'->>'nastaliq' AS new_nastaliq, data->'meanings'->0->'translations'->>'primary' AS primary, jsonb_array_length(data->'meanings') AS meanings FROM word_definitions WHERE word_lower IN ($wordListSql) ORDER BY word_lower;") | Out-Null
    $sql.AppendLine("COMMIT;") | Out-Null
} else {
    $sql.AppendLine("ROLLBACK;") | Out-Null
}

$conn = Convert-ToPsqlConnStr (Get-AzureConnectionString)
$output = $sql.ToString() | docker compose exec -T postgres psql $conn -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) { throw "Azure semantic patch load failed." }

Write-Host $output
if ($Apply) {
    Write-Host "Applied semantic patches. Backup run_id: $runId" -ForegroundColor Green
} else {
    Write-Host "Dry run complete. Re-run with -Apply to update Azure." -ForegroundColor Yellow
}
