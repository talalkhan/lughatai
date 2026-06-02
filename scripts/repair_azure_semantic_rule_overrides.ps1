# =============================================================================
# scripts/repair_azure_semantic_rule_overrides.ps1
#
# Applies small deterministic semantic/display repairs to Azure word_definitions.
# Intended for high-confidence fixes only; every old row is backed up first.
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

$repairs = @(
    @{ word = "topology"; primary = "ٹاپولوجی"; roman = "topology"; note = "fix mixed Latin/Nastaliq script display" },
    @{ word = "anorchi"; primary = "زینتی پودا"; roman = "zeenati poda"; note = "replace malformed mixed-script display with semantic Urdu alternative" },
    @{ word = "dhooti"; primary = "دھوتی"; roman = "dhoti"; note = "fix mixed Latin/Nastaliq script display" },
    @{ word = "ganjas"; primary = "گنجے"; roman = "ganjay"; note = "replace malformed mixed-script display with Urdu plural" },
    @{ word = "gubat"; primary = "دھندلکا"; roman = "dhundalka"; note = "replace malformed mixed-script display with semantic Urdu alternative" },
    @{ word = "harre"; primary = "جھاڑی"; roman = "jhaari"; note = "replace malformed mixed-script display with semantic Urdu alternative" },
    @{ word = "hurray"; primary = "خوشی کا نعرہ"; roman = "khushi ka naara"; note = "replace malformed mixed-script display with semantic Urdu phrase" },
    @{ word = "hutzpa"; primary = "ڈھٹائی"; roman = "dhitai"; note = "replace malformed mixed-script display with natural Urdu" },
    @{ word = "mudras"; primary = "ہاتھ کے اشارے"; roman = "haath ke isharay"; note = "replace mixed-script display with semantic Urdu plural" },
    @{ word = "nobleman"; primary = "نواب"; roman = "nawab"; note = "replace mixed-script primary with natural Urdu title" },
    @{ word = "petara"; primary = "پٹارا"; roman = "pitara"; note = "fix mixed Latin/Nastaliq script display" },
    @{ word = "roulette"; primary = "رولیٹ"; roman = "roulette"; note = "fix mixed Latin/Nastaliq script display" },
    @{ word = "ultra"; primary = "انتہائی"; roman = "intehai"; alternatives = @("بہت زیادہ", "غیر معمولی", "حد سے زیادہ"); alternatives_roman = @("bohat zyada", "ghair mamooli", "had se zyada"); note = "promote semantic Urdu primary for extreme-degree adjective/prefix" },
    @{ word = "beaker"; primary = "لیبارٹری کا پیالہ"; roman = "laboratory ka piyala"; alternatives = @("بیکر", "شیشی", "آزمایشگاهی پیالہ"); alternatives_roman = @("beaker", "sheeshi", "azmaishgahi piyala"); note = "replace malformed transliteration with clearer lab-vessel primary" },
    @{ word = "gorges"; primary = "تنگ گھاٹیاں"; roman = "tang ghaatiyan"; alternatives = @("گہری گھاٹیاں", "تنگ وادیاں"); alternatives_roman = @("gehri ghaatiyan", "tang wadiyan"); note = "replace English plural transliteration and wrong alternative with semantic Urdu plural" },
    @{ word = "antihero"; primary = "غیر روایتی ہیرو"; roman = "ghair riwayati hero"; alternatives = @("اینٹی ہیرو", "غیر ہیرو"); alternatives_roman = @("anti hero", "ghair hero"); note = "replace malformed transliteration and bad alternative with natural literary sense" },
    @{ word = "gali"; primary = "گالی"; roman = "gali"; alternatives = @("توہین", "بدزبانی", "بدتمیزی"); alternatives_roman = @("tauheen", "badzubani", "badtameezi"); note = "remove offensive/slur alternative and keep clean learner-safe alternatives" }
)

Write-Host ""
Write-Host "Semantic rule override repair" -ForegroundColor Cyan
Write-Host "-----------------------------" -ForegroundColor DarkGray
Write-Host "  Rows:   $($repairs.Count)"
Write-Host "  Target: Azure production database"
Write-Host "  Mode:   $(if ($Apply) { 'APPLY' } else { 'DRY RUN' })"

$runId = [Guid]::NewGuid().ToString()
$wordListSql = ($repairs | ForEach-Object { "'" + (Escape-SqlLiteral $_.word) + "'" }) -join ","

$sql = [System.Text.StringBuilder]::new()
$sql.AppendLine("BEGIN;") | Out-Null
$sql.AppendLine("CREATE TABLE IF NOT EXISTS semantic_rule_repair_backup (id bigserial PRIMARY KEY, run_id uuid NOT NULL, word text NOT NULL, backed_up_at timestamptz NOT NULL DEFAULT now(), old_model text, old_data jsonb NOT NULL, note text);") | Out-Null
$sql.AppendLine("SELECT word, model, data->'script_variants'->>'nastaliq' AS old_nastaliq, data->'meanings'->0->'translations'->>'primary' AS old_primary FROM word_definitions WHERE word_lower IN ($wordListSql) ORDER BY word_lower;") | Out-Null

if ($Apply) {
    foreach ($repair in $repairs) {
        $wordEsc = Escape-SqlLiteral $repair.word
        $primaryEsc = Escape-SqlLiteral $repair.primary
        $romanEsc = Escape-SqlLiteral $repair.roman
        $noteEsc = Escape-SqlLiteral $repair.note
        $nowEsc = Escape-SqlLiteral ([DateTime]::UtcNow.ToString("O"))

        $sql.AppendLine("INSERT INTO semantic_rule_repair_backup (run_id, word, old_model, old_data, note) SELECT '$runId'::uuid, word, model, data, '$noteEsc' FROM word_definitions WHERE word_lower = '$wordEsc';") | Out-Null
        $dataExpr = "jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(data, '{script_variants,nastaliq}', to_jsonb('$primaryEsc'::text), true), '{script_variants,roman_urdu}', to_jsonb('$romanEsc'::text), true), '{meanings,0,translations,primary}', to_jsonb('$primaryEsc'::text), true), '{meanings,0,translations,primary_roman}', to_jsonb('$romanEsc'::text), true), '{_meta,semantic_rule_repair}', 'true'::jsonb, true), '{_meta,semantic_rule_repaired_at}', to_jsonb('$nowEsc'::text), true)"
        if ($repair.ContainsKey("alternatives")) {
            $altsJson = ($repair.alternatives | ConvertTo-Json -Compress)
            $altsRomanJson = ($repair.alternatives_roman | ConvertTo-Json -Compress)
            $altsEsc = Escape-SqlLiteral $altsJson
            $altsRomanEsc = Escape-SqlLiteral $altsRomanJson
            $dataExpr = "jsonb_set(jsonb_set($dataExpr, '{meanings,0,translations,alternatives}', '$altsEsc'::jsonb, true), '{meanings,0,translations,alternatives_roman}', '$altsRomanEsc'::jsonb, true)"
        }
        $sql.AppendLine("UPDATE word_definitions SET data = $dataExpr, updated_at = now() WHERE word_lower = '$wordEsc';") | Out-Null
    }
    $sql.AppendLine("SELECT word, model, data->'script_variants'->>'nastaliq' AS new_nastaliq, data->'meanings'->0->'translations'->>'primary' AS new_primary, data->'meanings'->0->'translations'->>'primary_roman' AS new_primary_roman FROM word_definitions WHERE word_lower IN ($wordListSql) ORDER BY word_lower;") | Out-Null
    $sql.AppendLine("COMMIT;") | Out-Null
} else {
    $sql.AppendLine("ROLLBACK;") | Out-Null
}

$conn = Convert-ToPsqlConnStr (Get-AzureConnectionString)
$output = $sql.ToString() | docker compose exec -T postgres psql $conn -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) { throw "Azure semantic rule repair failed." }

Write-Host $output
if ($Apply) {
    Write-Host "Applied semantic rule repairs. Backup run_id: $runId" -ForegroundColor Green
} else {
    Write-Host "Dry run complete. Re-run with -Apply to update Azure." -ForegroundColor Yellow
}
