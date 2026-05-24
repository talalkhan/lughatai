-- Show raw _meta and etymology for a canary word
SELECT
  word,
  data->'_meta' AS meta,
  jsonb_typeof(data->'etymology') AS etymology_type,
  LEFT(data->>'etymology', 80) AS etymology_preview
FROM word_definitions
WHERE word = 'avouch';

-- Also check: does the data JSON even have a stage key at all anywhere?
SELECT word, data->'_meta' AS meta
FROM word_definitions
WHERE data->'_meta' ? 'stage'
LIMIT 5;
