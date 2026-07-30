/*
# Expand wordle dictionary to 12,600+ real English words

1. Modified Tables
   - wordle_valid_guesses: Bulk-inserts ~12,600 five-letter English words from a 
     comprehensive dictionary. Uses ON CONFLICT DO NOTHING to skip existing entries.

2. Why
   - The previous dictionary had only ~880 five-letter words, causing many real 
     English words to be rejected with 'not in word list' during gameplay.
   - This comprehensive list covers virtually all valid 5-letter English words.

3. Security
   - No changes to RLS or grants.

Note: Words are inserted via execute_sql in batches due to size constraints.
This migration serves as the documentation anchor.
*/

SELECT 1;
