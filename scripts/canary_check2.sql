-- Check 2 (corrected): headword drift — DB key vs AI-returned word in JSON
SELECT word AS db_key, data->>'word' AS ai_returned_word
FROM word_definitions
ORDER BY updated_at DESC
LIMIT 50;

-- Check 4: _meta.stage field presence
SELECT
  COUNT(1) AS total,
  COUNT(CASE WHEN data->'_meta'->>'stage' = 'core' THEN 1 END) AS stage_core,
  COUNT(CASE WHEN data->'_meta'->>'stage' IS NULL THEN 1 END) AS stage_missing
FROM word_definitions
ORDER BY updated_at DESC;

-- Check 5: how many of the 50 canary words have etymology vs null
SELECT
  COUNT(1) AS total,
  COUNT(CASE WHEN data->>'etymology' IS NOT NULL AND data->>'etymology' != 'null' THEN 1 END) AS etymology_present,
  COUNT(CASE WHEN data->>'memory_tip' IS NOT NULL AND data->>'memory_tip' != 'null' THEN 1 END) AS memory_tip_present
FROM word_definitions
ORDER BY updated_at DESC
LIMIT 50;

-- Check 6: sample one full _meta block to see if stage is in there at all
SELECT word, data->'_meta' AS meta
FROM word_definitions
ORDER BY updated_at DESC
LIMIT 3;
