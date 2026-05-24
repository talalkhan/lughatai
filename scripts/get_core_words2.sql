SELECT word FROM word_definitions WHERE data->'_meta'->>'stage' = 'core' AND word IN ('azure','auscultation','auxiliary','business','busy','butter','button') ORDER BY word;
