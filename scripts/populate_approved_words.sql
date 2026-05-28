-- Populate approved_words from the current database's word_queue.
-- This is safe to run repeatedly and does not enable the batch processor.
--
-- Use this when word_queue already exists in the target DB:
--   Get-Content scripts\populate_approved_words.sql |
--     docker compose exec -T postgres psql -U postgres -d lughatai

CREATE TABLE IF NOT EXISTS approved_words (
    word text PRIMARY KEY,
    source text NOT NULL DEFAULT 'manual',
    priority integer NOT NULL DEFAULT 3,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_approved_words_priority
ON approved_words(priority);

INSERT INTO approved_words (word, source, priority)
SELECT lower(word), 'word_queue', min(priority)
FROM word_queue
GROUP BY lower(word)
ON CONFLICT (word) DO UPDATE
SET priority = LEAST(approved_words.priority, EXCLUDED.priority);

SELECT
    source,
    priority,
    count(*) AS approved_count
FROM approved_words
GROUP BY source, priority
ORDER BY source, priority;
