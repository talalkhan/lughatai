SELECT word, data->'_meta' as meta, data ? 'etymology' as has_etymology, data->>'etymology' IS NOT NULL as etymology_has_value FROM word_definitions WHERE word = 'auscultation';
