/*
# Add Dynamic Text Overlay Fields to id_card_config

## Summary
The ID card front template no longer bakes in the staff member's photo,
name or email. Those are drawn dynamically by the app on top of the
template so each staff member sees their real details. This migration
adds the layout knobs for that text block.

## Modified Tables
- id_card_config: adds columns describing where the dynamic text block
  (full name, email, staff ID) sits on the front of the card, its
  colour and font sizes. All existing rows keep working because every
  new column has a sensible default.

New columns:
- text_x, text_y: top-left of the text block as a percent of the card.
- text_width: width of the text block as a percent of the card.
- text_align: how the three lines line up inside the block.
- text_color: hex colour used for all three lines.
- text_name_size, text_email_size, text_staff_id_size: base font sizes
  (in pixels at the base card_width_px) which the preview scales as
  the card size changes.
- text_show_staff_id: toggle for whether the staff ID line is shown.

## Notes
1. Defaults are chosen to line up with the green banner at the bottom
   of the Sycamore card template referenced by the operations team.
2. No data is dropped or renamed - this is an additive change only.
*/

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='text_x') THEN
    ALTER TABLE id_card_config ADD COLUMN text_x numeric NOT NULL DEFAULT 5;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='text_y') THEN
    ALTER TABLE id_card_config ADD COLUMN text_y numeric NOT NULL DEFAULT 78;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='text_width') THEN
    ALTER TABLE id_card_config ADD COLUMN text_width numeric NOT NULL DEFAULT 90;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='text_align') THEN
    ALTER TABLE id_card_config ADD COLUMN text_align text NOT NULL DEFAULT 'center';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='text_color') THEN
    ALTER TABLE id_card_config ADD COLUMN text_color text NOT NULL DEFAULT '#0f2946';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='text_name_size') THEN
    ALTER TABLE id_card_config ADD COLUMN text_name_size numeric NOT NULL DEFAULT 26;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='text_email_size') THEN
    ALTER TABLE id_card_config ADD COLUMN text_email_size numeric NOT NULL DEFAULT 15;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='text_staff_id_size') THEN
    ALTER TABLE id_card_config ADD COLUMN text_staff_id_size numeric NOT NULL DEFAULT 15;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='id_card_config' AND column_name='text_show_staff_id') THEN
    ALTER TABLE id_card_config ADD COLUMN text_show_staff_id boolean NOT NULL DEFAULT true;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='id_card_config_text_align_check') THEN
    ALTER TABLE id_card_config
      ADD CONSTRAINT id_card_config_text_align_check
      CHECK (text_align IN ('left', 'center', 'right'));
  END IF;
END $$;