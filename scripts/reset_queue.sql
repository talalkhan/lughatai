-- Reset words that failed due to rate-limiting (429) — these are timing failures, not content failures
UPDATE word_queue
SET status = 'pending', attempts = 0, error_message = NULL, updated_at = now()
WHERE status = 'failed' AND error_message LIKE '%429%';

-- Also zero out accumulated attempts on pending words that got partial attempt counts from old runs
-- (these are safe to retry from 0 since they never actually produced bad content)
UPDATE word_queue
SET attempts = 0, error_message = NULL, updated_at = now()
WHERE status = 'pending' AND attempts > 0;

SELECT status, COUNT(*) FROM word_queue GROUP BY status ORDER BY status;
