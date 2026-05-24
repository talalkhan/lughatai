# =============================================================================
# scripts/process_word_list.ps1
#
# Converts the raw Moby/SCOWL word list (466K entries) into a clean,
# frequency-sorted queue ready for UrduMeaning's word_queue table.
#
# What it does:
#   1. Downloads a 50K frequency list from hermitdave/FrequencyWords (cached)
#   2. Reads the source word list (default: Moby words.txt)
#   3. Filters out proper nouns, abbreviations, numbers, symbols, hyphens
#   4. Assigns priority tiers using the frequency list
#   5. Writes a bulk-insert SQL file (word_queue_bulk.sql)
#   6. Optionally loads it straight into Postgres via Docker
#
# Usage:
#   # Dry run - just show statistics:
#   .\scripts\process_word_list.ps1
#
#   # Generate SQL file only:
#   .\scripts\process_word_list.ps1 -OutputSql
#
#   # Generate SQL and load into Docker Postgres:
#   .\scripts\process_word_list.ps1 -OutputSql -LoadToDb
#
#   # Custom source file:
#   .\scripts\process_word_list.ps1 -SourceFile "C:\mywords.txt" -OutputSql -LoadToDb
#
# Priority tiers:
#   P1 (top 3000 by frequency)    -> generated first, best quality (Sonnet/GPT-4o)
#   P2 (rank 3001-25000)          -> generated second (Haiku/GPT-4o-mini)
#   P3 (rank 25001+, or unranked) -> generated last, bulk model
#
# Output: scripts/words/processed/word_queue_bulk.sql
# Load:   Get-Content ...\word_queue_bulk.sql | docker compose exec -T postgres psql -U postgres -d lughatai
# =============================================================================

param(
    # Source word list (Moby/SCOWL or any plain-text one-word-per-line file)
    [string]$SourceFile = "C:\Users\talal\source\repos\Dictionary\DictionaryWebApi\words.txt",

    # Output directory for generated files
    [string]$OutputDir  = (Join-Path $PSScriptRoot "words\processed"),

    # Frequency list URL (hermitdave English 50K, format: "word count" per line)
    [string]$FreqUrl    = "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt",

    # Priority cutoffs (rank in frequency list)
    [int]$P1MaxRank  = 3000,    # rank 1-3000       -> priority 1
    [int]$P2MaxRank  = 25000,   # rank 3001-25000   -> priority 2
                                # rank 25001+        -> priority 3

    # Minimum word length to keep
    [int]$MinLength = 3,

    # Write the bulk SQL file
    [switch]$OutputSql,

    # After writing SQL, pipe it into the running Docker Postgres container
    [switch]$LoadToDb,

    # Rows per INSERT statement in the SQL file (tune if needed)
    [int]$BatchSize = 2000
)

$ErrorActionPreference = "Stop"

# --- helpers -----------------------------------------------------------------

function Write-Header([string]$title) {
    Write-Host ""
    Write-Host $title -ForegroundColor Cyan
    Write-Host ("-" * $title.Length) -ForegroundColor DarkGray
}

# --- stop-word list (won't be queued) ----------------------------------------
# These are function/grammar words with no dictionary value in an E->U context.
$StopWordSet = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@(
        'the','a','an','this','that','these','those','each','every','both',
        'all','some','any','no','such','few','own',
        'i','me','my','myself','you','your','yours','yourself','yourselves',
        'he','him','his','himself','she','her','hers','herself',
        'it','its','itself','we','us','our','ours','ourselves',
        'they','them','their','theirs','themselves',
        'who','whom','whose','which','what',
        'in','on','at','by','for','with','about','against','between','into',
        'through','during','before','after','above','below','to','from',
        'up','down','of','off','over','under','again','out','than',
        'and','but','or','nor','so','yet','although','because','since',
        'while','if','unless','until','when','where','as','though',
        'be','been','being','am','is','are','was','were',
        'do','does','did','have','has','had',
        'will','would','shall','should','may','might','must','can','could',
        'not','also','just','then','now','only','even','still','here','there',
        'very','too','so','well','back','however','already','ever','never',
        'often','always','perhaps','rather','quite','almost','enough',
        'one','two','three','four','five','six','seven','eight','nine','ten',
        'said','say','get','got','go','went','come','came','make','made',
        'know','think','take','see','look','want','give','use','find',
        'tell','ask','seem','feel','try','leave','call','keep','let',
        'begin','show','hear','play','run','move','live','believe','hold',
        'bring','happen','write','provide','sit','stand','lose','pay',
        'meet','include','continue','set','turn','put','mean','become'
    ),
    [System.StringComparer]::OrdinalIgnoreCase
)

# --- Step 1: ensure output directory -----------------------------------------

Write-Header "UrduMeaning - process_word_list.ps1"
Write-Host "  Source:     $SourceFile" -ForegroundColor Gray
Write-Host "  Output dir: $OutputDir"  -ForegroundColor Gray
Write-Host "  P1 cutoff:  rank <= $P1MaxRank"  -ForegroundColor Gray
Write-Host "  P2 cutoff:  rank <= $P2MaxRank"  -ForegroundColor Gray

if (-not (Test-Path $SourceFile)) {
    Write-Host ""
    Write-Host "  ERROR: Source file not found: $SourceFile" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Host "  OK Created output directory" -ForegroundColor Green
}

# --- Step 2: download or load frequency list ---------------------------------

Write-Header "Step 1/4: Loading frequency list"

$freqCachePath = Join-Path $OutputDir "_freq_cache.txt"

if (Test-Path $freqCachePath) {
    Write-Host "  Using cached frequency list: $freqCachePath" -ForegroundColor White
} else {
    Write-Host "  Downloading frequency list from GitHub..." -ForegroundColor White
    try {
        Invoke-WebRequest -Uri $FreqUrl -OutFile $freqCachePath -UseBasicParsing
        Write-Host "  OK Downloaded and cached to $freqCachePath" -ForegroundColor Green
    } catch {
        Write-Host "  ! Download failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  ! Continuing without frequency data - all words will be priority 3." -ForegroundColor Yellow
        $freqCachePath = $null
    }
}

# Build priority HashSets: p1Set contains the top P1MaxRank words,
# p2Set contains the top P2MaxRank words.
# Using for-loop with index avoids the PowerShell foreach+hashtable bug.
$p1Set = [System.Collections.Generic.HashSet[string]]::new($P1MaxRank, [System.StringComparer]::OrdinalIgnoreCase)
$p2Set = [System.Collections.Generic.HashSet[string]]::new($P2MaxRank, [System.StringComparer]::OrdinalIgnoreCase)

if ($freqCachePath -and (Test-Path $freqCachePath)) {
    $freqLines = [System.IO.File]::ReadAllLines($freqCachePath, [System.Text.Encoding]::UTF8)
    $freqCount = $freqLines.Length

    for ($fi = 0; $fi -lt [Math]::Min($P2MaxRank, $freqCount); $fi++) {
        $spIdx = $freqLines[$fi].IndexOf(' ')
        $fw = if ($spIdx -gt 0) { $freqLines[$fi].Substring(0, $spIdx).ToLowerInvariant() } else { $freqLines[$fi].ToLowerInvariant() }
        if ($fw -ne '') {
            if ($fi -lt $P1MaxRank) { [void]$p1Set.Add($fw) }
            [void]$p2Set.Add($fw)
        }
    }
    Write-Host "  OK Frequency data: $($p1Set.Count) P1 words, $($p2Set.Count) P2 words" -ForegroundColor Green
} else {
    Write-Host "  No frequency data - all words will be priority 3" -ForegroundColor Yellow
}

# --- Step 3: read and filter the source word list ----------------------------

Write-Header "Step 2/4: Filtering word list"
Write-Host "  Reading $SourceFile ..." -ForegroundColor White

# Word storage: three Lists, one per priority tier.
# Using Lists avoids the foreach+hashtable bug seen with @{} and Dictionary.
$bucket1 = [System.Collections.Generic.List[string]]::new()   # priority 1
$bucket2 = [System.Collections.Generic.List[string]]::new()   # priority 2
$bucket3 = [System.Collections.Generic.List[string]]::new()   # priority 3

# HashSet for O(1) deduplication (same word appearing multiple times in input)
$seenWords = [System.Collections.Generic.HashSet[string]]::new(400000, [System.StringComparer]::OrdinalIgnoreCase)

# Counters
$totalLines     = 0
$filtUppercase  = 0
$filtDigit      = 0
$filtSpecial    = 0
$filtHyphen     = 0
$filtTooShort   = 0
$filtStopWord   = 0
$filtDuplicate  = 0

# Regex for special characters (compiled for speed across 466K lines)
$specialRx = [System.Text.RegularExpressions.Regex]::new(
    '[./\\@#$%^&*()+={}\[\]|<>?!;:,"''`~_]',
    [System.Text.RegularExpressions.RegexOptions]::Compiled
)

foreach ($line in [System.IO.File]::ReadLines($SourceFile)) {
    $totalLines++
    $word = $line.Trim()
    if ($word.Length -eq 0) { continue }

    # Filter: starts with uppercase (proper noun, acronym, Title Case name)
    if ([char]::IsUpper($word[0])) { $filtUppercase++; continue }

    # Filter: contains any uppercase letter (camelCase like iPhone, eBay)
    $hasUpperMid = $false
    for ($ci = 1; $ci -lt $word.Length; $ci++) {
        if ([char]::IsUpper($word[$ci])) { $hasUpperMid = $true; break }
    }
    if ($hasUpperMid) { $filtUppercase++; continue }

    # Filter: contains a digit
    $hasDigit = $false
    for ($ci = 0; $ci -lt $word.Length; $ci++) {
        if ([char]::IsDigit($word[$ci])) { $hasDigit = $true; break }
    }
    if ($hasDigit) { $filtDigit++; continue }

    # Filter: contains special characters (punctuation, symbols, underscores)
    if ($specialRx.IsMatch($word)) { $filtSpecial++; continue }

    # Filter: hyphenated compounds (e.g. "well-being" - hard to translate as unit)
    if ($word.IndexOf('-') -ge 0) { $filtHyphen++; continue }

    # Filter: too short
    if ($word.Length -lt $MinLength) { $filtTooShort++; continue }

    # Filter: stop word (function/grammar word)
    if ($StopWordSet.Contains($word)) { $filtStopWord++; continue }

    # Deduplicate (Moby list has duplicates from different sub-lists)
    if ($seenWords.Contains($word)) { $filtDuplicate++; continue }
    [void]$seenWords.Add($word)

    # Assign priority tier and add to the appropriate bucket
    if ($p1Set.Contains($word)) {
        $bucket1.Add($word)
    } elseif ($p2Set.Contains($word)) {
        $bucket2.Add($word)
    } else {
        $bucket3.Add($word)
    }
}

$totalKept = $bucket1.Count + $bucket2.Count + $bucket3.Count

Write-Host "  OK Read $totalLines lines" -ForegroundColor Green
Write-Host "  Filtered breakdown:" -ForegroundColor White
Write-Host "    Uppercase/proper nouns : $filtUppercase" -ForegroundColor Gray
Write-Host "    Contains digit         : $filtDigit"     -ForegroundColor Gray
Write-Host "    Special characters     : $filtSpecial"   -ForegroundColor Gray
Write-Host "    Hyphenated compounds   : $filtHyphen"    -ForegroundColor Gray
Write-Host "    Too short (< $MinLength chars)  : $filtTooShort"  -ForegroundColor Gray
Write-Host "    Stop words             : $filtStopWord"  -ForegroundColor Gray
Write-Host "    Duplicates             : $filtDuplicate" -ForegroundColor Gray
Write-Host ""
Write-Host "  OK $totalKept unique words passed filtering" -ForegroundColor Green
Write-Host "  Priority breakdown:" -ForegroundColor White
Write-Host "    P1 (rank 1-$P1MaxRank, Sonnet/GPT-4o)     : $($bucket1.Count) words" -ForegroundColor White
Write-Host "    P2 (rank $($P1MaxRank+1)-$P2MaxRank, Haiku/GPT-4o-mini) : $($bucket2.Count) words" -ForegroundColor White
Write-Host "    P3 (unranked, Haiku/GPT-4o-mini)   : $($bucket3.Count) words" -ForegroundColor Gray

# --- Step 4 (optional): write SQL file ---------------------------------------

if (-not $OutputSql -and -not $LoadToDb) {
    Write-Header "Done (dry run)"
    Write-Host "  Run with -OutputSql to generate the SQL file." -ForegroundColor Yellow
    Write-Host "  Run with -OutputSql -LoadToDb to generate and load directly." -ForegroundColor Yellow
    exit 0
}

Write-Header "Step 3/4: Writing SQL"

$sqlPath = Join-Path $OutputDir "word_queue_bulk.sql"

# Build sorted output: P1 first, then P2, then P3 (alphabetical within each tier)
$allWords = [System.Collections.Generic.List[object]]::new($totalKept)
foreach ($w in $bucket1) { $allWords.Add([PSCustomObject]@{Word=$w; Priority=1}) }
foreach ($w in $bucket2) { $allWords.Add([PSCustomObject]@{Word=$w; Priority=2}) }
foreach ($w in $bucket3) { $allWords.Add([PSCustomObject]@{Word=$w; Priority=3}) }

$batchCount = [Math]::Ceiling($totalKept / $BatchSize)
Write-Host "  Writing $totalKept words in $batchCount batches to:" -ForegroundColor White
Write-Host "  $sqlPath" -ForegroundColor Gray

$sw = [System.IO.StreamWriter]::new($sqlPath, $false, [System.Text.Encoding]::UTF8)

try {
    $sw.WriteLine("-- =============================================================================")
    $sw.WriteLine("-- UrduMeaning word_queue bulk insert")
    $sw.WriteLine("-- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $sw.WriteLine("-- Total words: $totalKept  (P1=$($bucket1.Count) P2=$($bucket2.Count) P3=$($bucket3.Count))")
    $sw.WriteLine("-- Load command:")
    $sw.WriteLine("--   Get-Content ""$sqlPath"" | docker compose exec -T postgres psql -U postgres -d lughatai")
    $sw.WriteLine("-- =============================================================================")
    $sw.WriteLine("")
    $sw.WriteLine("-- Stage words into a temp table, then merge (skips already-defined and already-queued words)")
    $sw.WriteLine("BEGIN;")
    $sw.WriteLine("")
    $sw.WriteLine("CREATE TEMP TABLE _wq_stage (word text, priority int) ON COMMIT DROP;")
    $sw.WriteLine("")

    $written = 0
    $i = 0
    while ($i -lt $totalKept) {
        $end   = [Math]::Min($i + $BatchSize - 1, $totalKept - 1)
        $count = $end - $i + 1

        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine("INSERT INTO _wq_stage (word, priority) VALUES")
        for ($j = $i; $j -le $end; $j++) {
            $item = $allWords[$j]
            $escaped = $item.Word -replace "'", "''"
            $comma = if ($j -lt $end) { "," } else { ";" }
            [void]$sb.AppendLine("  ('$escaped', $($item.Priority))$comma")
        }
        $sw.Write($sb.ToString())
        $sw.WriteLine("")

        $written += $count
        $i        = $end + 1

        if (($written % 20000) -eq 0 -or $written -eq $totalKept) {
            $pct = [Math]::Round($written / $totalKept * 100)
            Write-Host "  Written $written / $totalKept ($pct%)" -ForegroundColor Gray
        }
    }

    $sw.WriteLine("-- Merge: skip words already generated, skip duplicate queue entries")
    $sw.WriteLine("INSERT INTO word_queue (word, priority)")
    $sw.WriteLine("SELECT s.word, s.priority")
    $sw.WriteLine("FROM   _wq_stage s")
    $sw.WriteLine("WHERE  NOT EXISTS (")
    $sw.WriteLine("           SELECT 1 FROM word_definitions wd")
    $sw.WriteLine("           WHERE wd.word_lower = lower(s.word)")
    $sw.WriteLine("       )")
    $sw.WriteLine("ON CONFLICT (word) DO NOTHING;")
    $sw.WriteLine("")
    $sw.WriteLine("COMMIT;")
    $sw.WriteLine("")
    $sw.WriteLine("-- Final queue status after insert:")
    $sw.WriteLine("SELECT status, COUNT(*) as count FROM word_queue GROUP BY status ORDER BY status;")
}
finally {
    $sw.Close()
}

$sqlSizeMb = [Math]::Round((Get-Item $sqlPath).Length / 1MB, 1)
Write-Host "  OK Wrote $totalKept words -> $sqlPath ($sqlSizeMb MB)" -ForegroundColor Green

# --- Step 5 (optional): load into Postgres -----------------------------------

if (-not $LoadToDb) {
    Write-Header "Done"
    Write-Host ""
    Write-Host "  To load into the running Docker Postgres:" -ForegroundColor Yellow
    Write-Host "  Get-Content ""$sqlPath"" | docker compose exec -T postgres psql -U postgres -d lughatai" -ForegroundColor White
    Write-Host ""
    Write-Host "  Or with psql directly (if on PATH):" -ForegroundColor Yellow
    Write-Host "  psql -h localhost -p 5433 -U postgres -d lughatai -f ""$sqlPath""" -ForegroundColor White
    Write-Host ""
    exit 0
}

Write-Header "Step 4/4: Loading into Docker Postgres"
Write-Host "  Piping SQL into container (may take a minute for large files)..." -ForegroundColor White

try {
    $result = Get-Content $sqlPath | docker compose exec -T postgres psql -U postgres -d lughatai 2>&1
    $result | Select-Object -Last 25 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    Write-Host "  OK Load complete" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Load manually:" -ForegroundColor Yellow
    Write-Host "  Get-Content ""$sqlPath"" | docker compose exec -T postgres psql -U postgres -d lughatai" -ForegroundColor White
    exit 1
}

# --- summary -----------------------------------------------------------------

Write-Header "All done!"
Write-Host ""
Write-Host "  Words added to queue : ~$totalKept" -ForegroundColor Green
Write-Host "  P1 (best quality)    : $($bucket1.Count) words" -ForegroundColor White
Write-Host "  P2 (good quality)    : $($bucket2.Count) words" -ForegroundColor White
Write-Host "  P3 (bulk)            : $($bucket3.Count) words" -ForegroundColor White
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "    1. Make sure the API is running with BatchProcessor:Enabled = true" -ForegroundColor White
Write-Host "    2. Watch progress:  .\scripts\monitor_queue.ps1" -ForegroundColor White
Write-Host "    3. When done:       .\scripts\db_backup.ps1" -ForegroundColor White
Write-Host ""
