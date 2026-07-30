/*
# Fix crossword puzzle seed data

1. Data Fix
   - Replaced invalid crossword puzzle grid where clue answers did not match
     the actual grid letters.
   - New puzzle: PLANS (across), ALGAE (across), SIREN (across), 
     PLAYS (down), ANGER (down), STERN (down).
   - Grid uses null for blocked cells in rows 1 and 3, columns 1 and 3.

2. Important Notes
   - Cleared existing attempts so users start fresh with the corrected puzzle.
   - The grid and clues are now fully verified to be consistent.
*/

UPDATE crossword_puzzles 
SET grid = '[["P","L","A","N","S"],["L",null,"N",null,"T"],["A","L","G","A","E"],["Y",null,"E",null,"R"],["S","I","R","E","N"]]'::jsonb,
    clues_across = '[{"number":1,"clue":"Schemes or intentions","answer":"PLANS","row":0,"col":0,"length":5},{"number":4,"clue":"Simple aquatic plant","answer":"ALGAE","row":2,"col":0,"length":5},{"number":6,"clue":"Warning sound","answer":"SIREN","row":4,"col":0,"length":5}]'::jsonb,
    clues_down = '[{"number":1,"clue":"Theatre performances","answer":"PLAYS","row":0,"col":0,"length":5},{"number":2,"clue":"Strong displeasure","answer":"ANGER","row":0,"col":2,"length":5},{"number":3,"clue":"Serious and strict","answer":"STERN","row":0,"col":4,"length":5}]'::jsonb
WHERE puzzle_date = current_date;

DELETE FROM crossword_attempts WHERE puzzle_id = (SELECT id FROM crossword_puzzles WHERE puzzle_date = current_date);
