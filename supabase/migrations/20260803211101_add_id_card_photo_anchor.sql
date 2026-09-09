/*
# Add photo anchor control to id_card_config

## Summary
Adds a way for the operations team to anchor the staff photo from its
bottom edge instead of its top edge. When anchored from the bottom, the
photo's base sits exactly on a chosen line (for example, the boundary
between the white area and the green banner) no matter how tall the
photo slot is.

## Modified Tables
- id_card_config: additive column only, with a default that preserves
  the current behaviour.

New column:
- photo_anchor: 'top' (default, box grows downward from the top line) or
  'bottom' (box grows upward from the bottom line so the photo's base
  rests on the chosen position).

## Security
- No security changes. Existing RLS policies already govern this table.

## Notes
1. Additive change only - no data is dropped or renamed.
2. Default 'top' matches the previous rendering behaviour exactly.
*/

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='photo_anchor') THEN
    ALTER TABLE id_card_config ADD COLUMN photo_anchor text NOT NULL DEFAULT 'top';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='id_card_config_photo_anchor_check') THEN
    ALTER TABLE id_card_config
      ADD CONSTRAINT id_card_config_photo_anchor_check
      CHECK (photo_anchor IN ('top', 'bottom'));
  END IF;
END $$;