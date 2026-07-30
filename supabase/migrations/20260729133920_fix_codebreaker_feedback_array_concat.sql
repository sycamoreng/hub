/*
# Fix Code Breaker feedback function array concatenation

1. Modified Functions
   - `private.codebreaker_feedback(text[], text[])`: Fixed array concatenation 
     syntax. PostgreSQL was interpreting `fb || 'black'` as trying to parse 
     the string 'black' as an array literal. Changed to use `array_append()` 
     which properly appends a scalar element to a text array.

2. Important Notes
   - The old syntax `fb := fb || 'black'` caused "malformed array literal" error
     because PG's `||` operator on arrays expects both sides to be arrays or 
     tries to parse the right side as an array literal.
   - `array_append(fb, 'black')` is the correct way to append a scalar to an array.
*/

CREATE OR REPLACE FUNCTION private.codebreaker_feedback(p_secret text[], p_guess text[])
RETURNS text[]
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  fb text[] := '{}';
  used_secret boolean[] := ARRAY[false,false,false,false];
  used_guess boolean[] := ARRAY[false,false,false,false];
  blacks int := 0;
  whites int := 0;
BEGIN
  FOR i IN 1..4 LOOP
    IF p_guess[i] = p_secret[i] THEN
      blacks := blacks + 1;
      used_secret[i] := true;
      used_guess[i] := true;
    END IF;
  END LOOP;
  FOR i IN 1..4 LOOP
    IF NOT used_guess[i] THEN
      FOR j IN 1..4 LOOP
        IF NOT used_secret[j] AND p_guess[i] = p_secret[j] THEN
          whites := whites + 1;
          used_secret[j] := true;
          EXIT;
        END IF;
      END LOOP;
    END IF;
  END LOOP;
  FOR i IN 1..blacks LOOP fb := array_append(fb, 'black'); END LOOP;
  FOR i IN 1..whites LOOP fb := array_append(fb, 'white'); END LOOP;
  RETURN fb;
END;
$$;
