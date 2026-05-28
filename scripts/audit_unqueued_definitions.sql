-- Find generated definitions whose headword is not present in approved_words.
-- These are strong candidates for crawler/user typo pollution when live
-- generation was enabled without a deterministic validity gate.

SELECT
    wd.word,
    wd.model,
    wd.lookup_count,
    wd.created_at,
    wd.updated_at,
    wd.data->'_meta'->>'generated_by' AS generated_by,
    wd.data->'_meta'->>'stage' AS stage,
    length(wd.word) AS word_length
FROM word_definitions wd
LEFT JOIN approved_words aw ON aw.word = wd.word_lower
WHERE aw.word IS NULL
ORDER BY wd.created_at DESC, wd.word;

-- Count only:
-- SELECT count(*) AS unqueued_definition_count
-- FROM word_definitions wd
-- LEFT JOIN approved_words aw ON aw.word = wd.word_lower
-- WHERE aw.word IS NULL;

-- Deletion template. Review the SELECT results and take a fresh backup before
-- uncommenting this.
--
-- DELETE FROM word_definitions wd
-- WHERE NOT EXISTS (
--     SELECT 1
--     FROM approved_words aw
--     WHERE aw.word = wd.word_lower
-- );
