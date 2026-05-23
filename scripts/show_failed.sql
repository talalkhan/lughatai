SELECT word, attempts, SUBSTRING(error_message, 1, 100) as err FROM word_queue WHERE status = 'failed';
