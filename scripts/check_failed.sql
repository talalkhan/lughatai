SELECT word, attempts, SUBSTRING(error_message, 1, 120) as err FROM word_queue WHERE status = 'failed' LIMIT 10;
