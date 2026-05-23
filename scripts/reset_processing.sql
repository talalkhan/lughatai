-- Reset stuck 'processing' words left over from a killed API process
UPDATE word_queue SET status = 'pending', attempts = 0, error_message = NULL, updated_at = now() WHERE status = 'processing';
SELECT status, COUNT(*) FROM word_queue GROUP BY status ORDER BY status;
