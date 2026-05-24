-- Core fields presence across the 50 most recent words
SELECT
  SUM(CASE WHEN data->>'etymology' IS NOT NULL AND data->>'etymology' != 'null' THEN 1 ELSE 0 END) AS etymology_present,
  SUM(CASE WHEN data->>'memory_tip'  IS NOT NULL AND data->>'memory_tip'  != 'null' THEN 1 ELSE 0 END) AS memory_tip_present,
  SUM(CASE WHEN data->>'urdu_poetry' IS NOT NULL AND data->>'urdu_poetry' != 'null' THEN 1 ELSE 0 END) AS poetry_present,
  SUM(CASE WHEN data->>'urdu_proverb' IS NOT NULL AND data->>'urdu_proverb' != 'null' THEN 1 ELSE 0 END) AS proverb_present,
  SUM(CASE WHEN data->>'islamic_reference' IS NOT NULL AND data->>'islamic_reference' != 'null' THEN 1 ELSE 0 END) AS islamic_present,
  COUNT(1) AS total
FROM (SELECT data FROM word_definitions ORDER BY updated_at DESC LIMIT 50) sub;

-- _meta.stage across ALL definitions
SELECT
  data->'_meta'->>'stage' AS stage,
  COUNT(1)
FROM word_definitions
GROUP BY data->'_meta'->>'stage';
