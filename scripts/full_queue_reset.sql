-- Complete queue reset: zero ALL accumulated state on non-done words.
-- Use this after a series of debugging runs to get back to a pristine starting point.
UPDATE word_queue
SET status = 'pending', attempts = 0, error_message = NULL, updated_at = now()
WHERE status IN ('failed', 'processing')
   OR (status = 'pending' AND attempts > 0);

SELECT status, COUNT(*) FROM word_queue GROUP BY status ORDER BY status;
