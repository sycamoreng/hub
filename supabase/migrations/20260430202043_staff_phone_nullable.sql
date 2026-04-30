/*
  # Make staff_members.phone nullable

  Google sync may receive users without a phone number. The column
  previously had NOT NULL + default '', but the sync passes explicit
  null values for the phone field on updates, which violates the
  constraint. Allowing NULL (and keeping the '' default for manually
  created rows) resolves the sync error without any data loss.
*/

ALTER TABLE staff_members ALTER COLUMN phone DROP NOT NULL;
