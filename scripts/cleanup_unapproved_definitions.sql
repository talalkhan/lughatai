-- Review, quarantine, then delete generated definitions that are not approved.
--
-- Intended use:
--   1. Back up the DB first.
--   2. Ensure approved_words is populated.
--   3. Review the candidate SELECT below.
--   4. Run this script in a transaction.
--
-- Adjust this cutoff if the crawler pollution window changes.

BEGIN;

CREATE TABLE IF NOT EXISTS bad_word_definitions_quarantine
(LIKE word_definitions INCLUDING ALL);

-- Review candidates before deletion. These are generated rows created during
-- the crawler incident window whose headword is not in approved_words.
SELECT
    wd.id,
    wd.word,
    wd.model,
    wd.lookup_count,
    wd.created_at,
    wd.updated_at,
    wd.data->'_meta'->>'generated_by' AS generated_by,
    wd.data->'_meta'->>'stage' AS stage
FROM word_definitions wd
LEFT JOIN approved_words aw ON aw.word = wd.word_lower
WHERE aw.word IS NULL
  AND wd.created_at >= timestamptz '2026-05-26 00:00:00+00'
ORDER BY wd.created_at DESC, wd.word;

-- Quarantine first so rollback/recovery is possible even after commit.
INSERT INTO bad_word_definitions_quarantine
SELECT wd.*
FROM word_definitions wd
LEFT JOIN approved_words aw ON aw.word = wd.word_lower
WHERE aw.word IS NULL
  AND wd.created_at >= timestamptz '2026-05-26 00:00:00+00'
ON CONFLICT (id) DO NOTHING;

DELETE FROM word_definitions wd
USING bad_word_definitions_quarantine q
WHERE wd.id = q.id;

SELECT count(*) AS quarantined_rows
FROM bad_word_definitions_quarantine
WHERE created_at >= timestamptz '2026-05-26 00:00:00+00';

COMMIT;
