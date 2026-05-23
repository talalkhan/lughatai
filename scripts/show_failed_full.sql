SELECT word, attempts, error_message FROM word_queue WHERE status = 'failed' ORDER BY word;
