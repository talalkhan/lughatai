-- Check specifically the "avo*" words from my canary (lowest IDs reset from failed batches)
-- These are the actual canary words, distinct from live-processor output

-- Stage set correctly on canary words?
SELECT
  word,
  data->'_meta'->>'stage' AS stage,
  data->>'etymology' IS NULL AS etymology_null,
  data->>'memory_tip' IS NULL AS memory_tip_null,
  data->>'urdu_poetry' IS NULL AS poetry_null,
  data->>'urdu_proverb' IS NULL AS proverb_null
FROM word_definitions
WHERE word LIKE 'avo%'
ORDER BY word
LIMIT 20;

-- Summary: what stage distribution do the avo* words have?
SELECT
  data->'_meta'->>'stage' AS stage,
  COUNT(1) AS cnt,
  SUM(CASE WHEN data->>'etymology' IS NULL THEN 1 ELSE 0 END) AS etymology_null_count,
  SUM(CASE WHEN data->>'memory_tip' IS NULL THEN 1 ELSE 0 END) AS memory_tip_null_count
FROM word_definitions
WHERE word LIKE 'avo%'
GROUP BY data->'_meta'->>'stage';
