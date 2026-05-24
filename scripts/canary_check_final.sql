SELECT word, data->'_meta'->>'stage' as stage, data ? 'etymology' as has_etymology, data ? 'memory_tip' as has_memory_tip FROM word_definitions WHERE word = 'azure';
