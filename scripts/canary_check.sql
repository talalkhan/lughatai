-- Check 1: words stuck in processing from canary batch
SELECT COUNT(1) AS stuck_in_processing
FROM word_queue
WHERE status = 'processing'
  AND error_message LIKE 'batch:submitted:batch_6a126a9f6e7c81909d42ec33428b7c40%';

-- Check 2: headword drift - definitions where word doesn't match the queue word
-- Get the 50 words that were in this batch via done status + recent update
SELECT COUNT(1) AS headword_drift_count
FROM word_definitions wd
JOIN word_queue wq ON wq.word = wd.word
WHERE wq.status = 'done'
  AND wq.error_message LIKE 'batch:submitted:batch_6a126a9f6e7c81909d42ec33428b7c40%';

-- Check 3: sample the 50 most recently inserted definitions and check core field nulls
SELECT
  word,
  data->>'_meta' AS meta_stage,
  (data->>'etymology') IS NULL OR (data->>'etymology') = 'null' AS etymology_null,
  (data->>'memory_tip') IS NULL OR (data->>'memory_tip') = 'null' AS memory_tip_null,
  (data->>'urdu_poetry') IS NULL OR (data->>'urdu_poetry') = 'null' AS poetry_null,
  (data->>'urdu_proverb') IS NULL OR (data->>'urdu_proverb') = 'null' AS proverb_null,
  (data->>'islamic_reference') IS NULL OR (data->>'islamic_reference') = 'null' AS islamic_null
FROM word_definitions
ORDER BY updated_at DESC
LIMIT 50;
