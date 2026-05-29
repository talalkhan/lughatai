# =============================================================================
# scripts/prepare_openai_pilot_queue.ps1
#
# Loads a reviewed word list into the LOCAL Docker word_queue for an isolated
# OpenAI Batch API pilot. This does not call OpenAI and does not write to Azure.
#
# Usage:
#   .\scripts\prepare_openai_pilot_queue.ps1 `
#     -File scripts\words\processed\pilot_missing_500.txt `
#     -Priority 1
# =============================================================================

param(
    [Parameter(Mandatory)][string]$File,
    [ValidateRange(1,5)][int]$Priority = 1,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $File)) {
    Write-Host "File not found: $File" -ForegroundColor Red
    exit 1
}

$words = Get-Content $File -Encoding UTF8 |
    ForEach-Object { $_.Trim().ToLowerInvariant() } |
    Where-Object { $_ -ne "" -and -not $_.StartsWith("#") } |
    Sort-Object -Unique

$invalid = $words | Where-Object { $_ -notmatch '^[a-z]{3,64}$' } | Select-Object -First 10
if ($invalid) {
    Write-Host "Invalid words found. Fix the list before queueing:" -ForegroundColor Red
    $invalid | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    exit 1
}

if ($words.Count -eq 0) {
    Write-Host "No words found in $File" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Prepare local OpenAI pilot queue" -ForegroundColor Cyan
Write-Host "--------------------------------" -ForegroundColor DarkGray
Write-Host "  File:     $File" -ForegroundColor White
Write-Host "  Words:    $($words.Count)" -ForegroundColor White
Write-Host "  Priority: $Priority" -ForegroundColor White
Write-Host "  Target:   local Docker Postgres only" -ForegroundColor White
Write-Host ""

if (-not $Force) {
    $answer = Read-Host "Queue these words locally as pending priority $Priority? Type YES to continue"
    if ($answer -ne "YES") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 1
    }
}

$sql = [System.Text.StringBuilder]::new()
$sql.AppendLine("BEGIN;") | Out-Null
$sql.AppendLine("CREATE TEMP TABLE tmp_pilot_words(word text PRIMARY KEY);") | Out-Null
$sql.AppendLine("COPY tmp_pilot_words(word) FROM STDIN;") | Out-Null
foreach ($word in $words) {
    $sql.AppendLine($word) | Out-Null
}
$sql.AppendLine("\.") | Out-Null
$sql.AppendLine(@"
DO `$`$
BEGIN
    IF to_regclass('public.approved_words') IS NOT NULL THEN
        INSERT INTO approved_words (word, source, priority)
        SELECT word, 'openai_pilot', $Priority
        FROM tmp_pilot_words
        ON CONFLICT (word) DO UPDATE
        SET priority = LEAST(approved_words.priority, EXCLUDED.priority);
    END IF;
END
`$`$;

INSERT INTO word_queue (word, priority, status, attempts, error_message, updated_at)
SELECT word, $Priority, 'pending', 0, 'openai_pilot', now()
FROM tmp_pilot_words
ON CONFLICT (word) DO UPDATE
SET priority = EXCLUDED.priority,
    status = 'pending',
    attempts = 0,
    error_message = 'openai_pilot',
    updated_at = now();

COMMIT;

SELECT status, priority, COUNT(*)
FROM word_queue
WHERE priority = $Priority
GROUP BY status, priority
ORDER BY status, priority;
"@) | Out-Null

$result = $sql.ToString() | docker compose exec -T postgres psql -U postgres -d lughatai --set ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to prepare local queue." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host $result
Write-Host ""
Write-Host "Local pilot queue is ready." -ForegroundColor Green
