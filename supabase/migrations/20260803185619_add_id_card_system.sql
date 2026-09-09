/*
# Add ID Card System

## Summary
Adds a staff ID card feature so employees can upload their own photo
which then appears composited on top of an ID card template that the
company operations/marketing team has uploaded. Admins can view every
staff member's rendered ID card front + back to help them print.

## New Tables
1. id_card_config (singleton row, id=1)
   - front_template_url, back_template_url: URLs of the front and back
     card template images uploaded by an admin.
   - photo_x, photo_y, photo_width, photo_height: percentages (0-100)
     describing where on the front template the staff photo appears.
   - photo_shape: 'rectangle' or 'circle' visual crop.
   - card_width_px, card_height_px: preview dimensions for consistent
     rendering across staff and admin views.
   - updated_at.
2. staff_id_card_photos
   - user_id (uuid, PK, FK to auth.users): the staff member.
   - photo_url: uploaded staff portrait for the ID card.
   - updated_at.

## Security
- RLS enabled on both tables.
- id_card_config: any authenticated staff member can read; only admins
  with the 'id-cards' section permission can insert/update/delete.
- staff_id_card_photos: staff can read + write only their own row;
  admins with 'id-cards' permission can read + delete all rows so the
  marketing team can see every staff member's ID card and reset photos
  if needed.

## Notes
1. photo_shape defaults to 'rectangle' since most ID cards use a
   rectangular headshot slot.
2. Percentages let the same placement box work across preview sizes.
*/

CREATE TABLE IF NOT EXISTS id_card_config (
  id integer PRIMARY KEY DEFAULT 1,
  front_template_url text,
  back_template_url text,
  photo_x numeric NOT NULL DEFAULT 30,
  photo_y numeric NOT NULL DEFAULT 20,
  photo_width numeric NOT NULL DEFAULT 40,
  photo_height numeric NOT NULL DEFAULT 30,
  photo_shape text NOT NULL DEFAULT 'rectangle',
  card_width_px integer NOT NULL DEFAULT 400,
  card_height_px integer NOT NULL DEFAULT 630,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT id_card_config_singleton CHECK (id = 1),
  CONSTRAINT id_card_config_shape CHECK (photo_shape IN ('rectangle', 'circle'))
);

INSERT INTO id_card_config (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE id_card_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "id_card_config_select" ON id_card_config;
CREATE POLICY "id_card_config_select" ON id_card_config
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "id_card_config_insert" ON id_card_config;
CREATE POLICY "id_card_config_insert" ON id_card_config
  FOR INSERT TO authenticated
  WITH CHECK (private.admin_can('id-cards', 'update'));

DROP POLICY IF EXISTS "id_card_config_update" ON id_card_config;
CREATE POLICY "id_card_config_update" ON id_card_config
  FOR UPDATE TO authenticated
  USING (private.admin_can('id-cards', 'update'))
  WITH CHECK (private.admin_can('id-cards', 'update'));

DROP POLICY IF EXISTS "id_card_config_delete" ON id_card_config;
CREATE POLICY "id_card_config_delete" ON id_card_config
  FOR DELETE TO authenticated
  USING (private.admin_can('id-cards', 'delete'));


CREATE TABLE IF NOT EXISTS staff_id_card_photos (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  photo_url text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE staff_id_card_photos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "id_card_photos_select_own_or_admin" ON staff_id_card_photos;
CREATE POLICY "id_card_photos_select_own_or_admin" ON staff_id_card_photos
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR private.admin_can('id-cards', 'read')
  );

DROP POLICY IF EXISTS "id_card_photos_insert_own" ON staff_id_card_photos;
CREATE POLICY "id_card_photos_insert_own" ON staff_id_card_photos
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "id_card_photos_update_own_or_admin" ON staff_id_card_photos;
CREATE POLICY "id_card_photos_update_own_or_admin" ON staff_id_card_photos
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR private.admin_can('id-cards', 'update'))
  WITH CHECK (user_id = auth.uid() OR private.admin_can('id-cards', 'update'));

DROP POLICY IF EXISTS "id_card_photos_delete_own_or_admin" ON staff_id_card_photos;
CREATE POLICY "id_card_photos_delete_own_or_admin" ON staff_id_card_photos
  FOR DELETE TO authenticated
  USING (user_id = auth.uid() OR private.admin_can('id-cards', 'delete'));