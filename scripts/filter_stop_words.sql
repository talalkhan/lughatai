-- =============================================================================
-- scripts/filter_stop_words.sql
--
-- Remove function words from word_queue that are useless in an English-Urdu
-- dictionary (articles, pronouns, prepositions, conjunctions, auxiliaries).
-- Run this ONCE after seeding, before enabling the batch processor.
--
-- Usage:
--   docker compose exec -T postgres psql -U postgres -d lughatai < scripts/filter_stop_words.sql
-- =============================================================================

DELETE FROM word_queue WHERE word IN (
    -- Articles
    'the', 'a', 'an',

    -- Personal pronouns
    'i', 'me', 'my', 'myself',
    'you', 'your', 'yours', 'yourself', 'yourselves',
    'he', 'him', 'his', 'himself',
    'she', 'her', 'hers', 'herself',
    'it', 'its', 'itself',
    'we', 'us', 'our', 'ours', 'ourselves',
    'they', 'them', 'their', 'theirs', 'themselves',

    -- Demonstratives
    'this', 'that', 'these', 'those',

    -- Interrogatives / relatives
    'who', 'whom', 'whose', 'which', 'what',

    -- Prepositions
    'in', 'on', 'at', 'by', 'for', 'with', 'about', 'against',
    'between', 'into', 'through', 'during', 'before', 'after',
    'above', 'below', 'to', 'from', 'up', 'down', 'of', 'off',
    'over', 'under', 'again', 'out', 'than',

    -- Coordinating conjunctions
    'and', 'but', 'or', 'nor', 'so', 'yet',

    -- Subordinating conjunctions
    'although', 'because', 'since', 'while', 'if', 'unless',
    'until', 'when', 'where', 'as', 'though',

    -- Auxiliary / modal verbs (the base forms)
    'be', 'been', 'being', 'am', 'is', 'are', 'was', 'were',
    'do', 'does', 'did',
    'have', 'has', 'had',
    'will', 'would', 'shall', 'should',
    'may', 'might', 'must', 'can', 'could',

    -- Determiners & quantifiers
    'some', 'any', 'each', 'every', 'all', 'both', 'few',
    'more', 'most', 'no', 'such', 'own',

    -- Common adverbs with no translation value
    'not', 'also', 'just', 'then', 'now', 'only', 'even', 'still',
    'here', 'there', 'very', 'too', 'so', 'well', 'back',
    'however', 'already', 'ever', 'never', 'often', 'always',
    'perhaps', 'rather', 'quite', 'almost', 'enough',

    -- Numbers (words)
    'one', 'two', 'three', 'four', 'five', 'six', 'seven',
    'eight', 'nine', 'ten',

    -- Other high-frequency words with trivial dictionary value
    'said', 'say', 'get', 'got', 'go', 'went', 'come', 'came',
    'make', 'made', 'know', 'think', 'take', 'see', 'look',
    'want', 'give', 'use', 'find', 'tell', 'ask', 'seem',
    'feel', 'try', 'leave', 'call', 'keep', 'let', 'begin',
    'show', 'hear', 'play', 'run', 'move', 'live', 'believe',
    'hold', 'bring', 'happen', 'write', 'provide', 'sit', 'stand',
    'lose', 'pay', 'meet', 'include', 'continue', 'set', 'turn',
    'put', 'mean', 'become'
);

-- Report how many words remain
SELECT
    priority,
    COUNT(*) AS words_remaining
FROM word_queue
WHERE status = 'pending'
GROUP BY priority
ORDER BY priority;

SELECT COUNT(*) AS total_pending FROM word_queue WHERE status = 'pending';
