/*
# Add logo overlay and photo fit controls to id_card_config

## Summary
The ID card front now supports a company logo drawn as an overlay on top
of the template (like the photo and text blocks already are), and gives
finer control over how each staff photo sits inside its slot. This lets
the operations team place the Sycamore logo and stop portraits from being
awkwardly cropped.

## Modified Tables
- id_card_config: additive columns only. Every new column has a sensible
  default so existing rows keep working unchanged.

New columns:
- logo_url: image URL of the logo shown on the front (defaults to the
  bundled Sycamore wordmark).
- logo_show: toggle for whether the logo overlay is drawn.
- logo_x, logo_y: top-left of the logo as a percent of the card.
- logo_width: width of the logo as a percent of the card (height scales
  automatically to keep the logo's proportions).
- photo_fit: how the photo fills its slot - 'cover' fills and crops,
  'contain' shows the whole photo without cropping.
- photo_position: vertical alignment of the photo inside its slot when
  using 'cover' ('top', 'center' or 'bottom'), so faces can be centred.

## Security
- No security changes. Existing RLS policies already govern this table
  (any authenticated staff can read; only 'id-cards' admins can write).

## Notes
1. This is an additive change only - no data is dropped or renamed.
2. Defaults keep the previous behaviour: photo_fit 'cover' and
   photo_position 'center' match how photos were rendered before.
*/

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='logo_url') THEN
    ALTER TABLE id_card_config ADD COLUMN logo_url text DEFAULT '/sycamore-wordmark.png';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='logo_show') THEN
    ALTER TABLE id_card_config ADD COLUMN logo_show boolean NOT NULL DEFAULT true;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='logo_x') THEN
    ALTER TABLE id_card_config ADD COLUMN logo_x numeric NOT NULL DEFAULT 25;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='logo_y') THEN
    ALTER TABLE id_card_config ADD COLUMN logo_y numeric NOT NULL DEFAULT 6;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='logo_width') THEN
    ALTER TABLE id_card_config ADD COLUMN logo_width numeric NOT NULL DEFAULT 50;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='photo_fit') THEN
    ALTER TABLE id_card_config ADD COLUMN photo_fit text NOT NULL DEFAULT 'cover';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='photo_position') THEN
    ALTER TABLE id_card_config ADD COLUMN photo_position text NOT NULL DEFAULT 'center';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='id_card_config_photo_fit_check') THEN
    ALTER TABLE id_card_config
      ADD CONSTRAINT id_card_config_photo_fit_check
      CHECK (photo_fit IN ('cover', 'contain'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='id_card_config_photo_position_check') THEN
    ALTER TABLE id_card_config
      ADD CONSTRAINT id_card_config_photo_position_check
      CHECK (photo_position IN ('top', 'center', 'bottom'));
  END IF;
END $$;