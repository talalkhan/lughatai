SELECT word FROM word_definitions WHERE data->'_meta'->>'stage' = 'core' ORDER BY word LIMIT 20;
