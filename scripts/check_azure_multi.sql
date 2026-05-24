SELECT id, word, word_lower, data->'_meta' as meta FROM word_definitions WHERE word_lower = 'azure' ORDER BY id;
