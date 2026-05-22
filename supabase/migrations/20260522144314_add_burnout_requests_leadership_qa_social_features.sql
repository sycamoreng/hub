/*
  # Add Burnout Risk, Request Tracker, Leadership Q&A, Contractors, Analytics, and Social Features

  1. New Tables
    - `burnout_risk_flags` - tracks burnout risk indicators per staff member
    - `service_requests` - SLA/request tracker
    - `service_request_comments` - comments on requests
    - `leadership_questions` - Ask Leadership Anything
    - `leadership_question_votes` - upvotes on questions
    - `contractors` - vendor/contractor management
    - `headcount_plans` - headcount planning
    - `photo_wall_posts` - company photo wall
    - `photo_wall_likes` - likes on photos
    - `pet_profiles` - pet board
    - `pet_likes` - likes on pets
    - `playlist_weeks` - weekly playlists
    - `playlist_songs` - songs in playlists
    - `playlist_votes` - votes on songs

  2. Security
    - Enable RLS on all tables
    - Admin-only for burnout, contractors, headcount
    - Authenticated access for social features
    - Owner-based policies where applicable
*/

-- Burnout Risk Flags
CREATE TABLE IF NOT EXISTS burnout_risk_flags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid NOT NULL REFERENCES staff_members(id),
  risk_level text NOT NULL DEFAULT 'low' CHECK (risk_level IN ('low', 'medium', 'high', 'critical')),
  indicators jsonb NOT NULL DEFAULT '{}'::jsonb,
  flagged_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  notes text NOT NULL DEFAULT '',
  created_by uuid REFERENCES auth.users(id)
);

ALTER TABLE burnout_risk_flags ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can view burnout flags"
  ON burnout_risk_flags FOR SELECT
  TO authenticated
  USING (private.admin_can('burnout', 'read'));

CREATE POLICY "Admins can insert burnout flags"
  ON burnout_risk_flags FOR INSERT
  TO authenticated
  WITH CHECK (private.admin_can('burnout', 'create'));

CREATE POLICY "Admins can update burnout flags"
  ON burnout_risk_flags FOR UPDATE
  TO authenticated
  USING (private.admin_can('burnout', 'update'))
  WITH CHECK (private.admin_can('burnout', 'update'));

-- Service Requests (SLA Tracker)
CREATE TABLE IF NOT EXISTS service_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id uuid NOT NULL REFERENCES auth.users(id),
  category text NOT NULL DEFAULT 'other' CHECK (category IN ('it', 'facilities', 'hr', 'finance', 'other')),
  priority text NOT NULL DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
  subject text NOT NULL,
  description text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'waiting', 'resolved', 'closed')),
  assigned_to uuid REFERENCES auth.users(id),
  sla_hours int NOT NULL DEFAULT 48,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);

ALTER TABLE service_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own requests or admins all"
  ON service_requests FOR SELECT
  TO authenticated
  USING (requester_id = auth.uid() OR assigned_to = auth.uid() OR private.admin_can('requests', 'read'));

CREATE POLICY "Users can create requests"
  ON service_requests FOR INSERT
  TO authenticated
  WITH CHECK (requester_id = auth.uid());

CREATE POLICY "Admins and assignees can update requests"
  ON service_requests FOR UPDATE
  TO authenticated
  USING (assigned_to = auth.uid() OR private.admin_can('requests', 'update'))
  WITH CHECK (assigned_to = auth.uid() OR private.admin_can('requests', 'update'));

-- Service Request Comments
CREATE TABLE IF NOT EXISTS service_request_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES auth.users(id),
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE service_request_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Request participants can view comments"
  ON service_request_comments FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM service_requests sr
      WHERE sr.id = request_id
      AND (sr.requester_id = auth.uid() OR sr.assigned_to = auth.uid() OR private.admin_can('requests', 'read'))
    )
  );

CREATE POLICY "Participants can add comments"
  ON service_request_comments FOR INSERT
  TO authenticated
  WITH CHECK (
    author_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM service_requests sr
      WHERE sr.id = request_id
      AND (sr.requester_id = auth.uid() OR sr.assigned_to = auth.uid() OR private.admin_can('requests', 'read'))
    )
  );

-- Leadership Questions (Ask Leadership Anything)
CREATE TABLE IF NOT EXISTS leadership_questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id uuid NOT NULL REFERENCES auth.users(id),
  question text NOT NULL,
  is_anonymous boolean NOT NULL DEFAULT false,
  upvotes int NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'answered', 'archived')),
  answer text,
  answered_by uuid REFERENCES auth.users(id),
  answered_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE leadership_questions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can view non-archived questions"
  ON leadership_questions FOR SELECT
  TO authenticated
  USING (status != 'archived' OR private.admin_can('leadership_qa', 'read'));

CREATE POLICY "Authenticated users can ask questions"
  ON leadership_questions FOR INSERT
  TO authenticated
  WITH CHECK (author_id = auth.uid());

CREATE POLICY "Admins can update questions to answer"
  ON leadership_questions FOR UPDATE
  TO authenticated
  USING (private.admin_can('leadership_qa', 'update'))
  WITH CHECK (private.admin_can('leadership_qa', 'update'));

CREATE POLICY "Authors can delete own pending questions"
  ON leadership_questions FOR DELETE
  TO authenticated
  USING (author_id = auth.uid() AND status = 'pending');

-- Leadership Question Votes
CREATE TABLE IF NOT EXISTS leadership_question_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  question_id uuid NOT NULL REFERENCES leadership_questions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (question_id, user_id)
);

ALTER TABLE leadership_question_votes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can view question votes"
  ON leadership_question_votes FOR SELECT
  TO authenticated
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "Users can add question votes"
  ON leadership_question_votes FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can remove own question votes"
  ON leadership_question_votes FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

-- Contractors
CREATE TABLE IF NOT EXISTS contractors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  company text NOT NULL DEFAULT '',
  email text NOT NULL DEFAULT '',
  phone text NOT NULL DEFAULT '',
  role text NOT NULL DEFAULT '',
  department text NOT NULL DEFAULT '',
  contract_start date,
  contract_end date,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'terminated')),
  hourly_rate numeric,
  notes text NOT NULL DEFAULT '',
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE contractors ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can view contractors"
  ON contractors FOR SELECT
  TO authenticated
  USING (private.admin_can('contractors', 'read'));

CREATE POLICY "Admins can insert contractors"
  ON contractors FOR INSERT
  TO authenticated
  WITH CHECK (private.admin_can('contractors', 'create'));

CREATE POLICY "Admins can update contractors"
  ON contractors FOR UPDATE
  TO authenticated
  USING (private.admin_can('contractors', 'update'))
  WITH CHECK (private.admin_can('contractors', 'update'));

CREATE POLICY "Admins can delete contractors"
  ON contractors FOR DELETE
  TO authenticated
  USING (private.admin_can('contractors', 'delete'));

-- Headcount Plans
CREATE TABLE IF NOT EXISTS headcount_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  department text NOT NULL,
  role_title text NOT NULL,
  quarter text NOT NULL,
  planned_hires int NOT NULL DEFAULT 1,
  actual_hires int NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'approved', 'in_progress', 'filled', 'cancelled')),
  justification text NOT NULL DEFAULT '',
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE headcount_plans ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can view headcount plans"
  ON headcount_plans FOR SELECT
  TO authenticated
  USING (private.admin_can('headcount', 'read'));

CREATE POLICY "Admins can insert headcount plans"
  ON headcount_plans FOR INSERT
  TO authenticated
  WITH CHECK (private.admin_can('headcount', 'create'));

CREATE POLICY "Admins can update headcount plans"
  ON headcount_plans FOR UPDATE
  TO authenticated
  USING (private.admin_can('headcount', 'update'))
  WITH CHECK (private.admin_can('headcount', 'update'));

-- Photo Wall
CREATE TABLE IF NOT EXISTS photo_wall_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id uuid NOT NULL REFERENCES auth.users(id),
  image_url text NOT NULL,
  caption text NOT NULL DEFAULT '',
  event_name text,
  likes_count int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE photo_wall_posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can view photos"
  ON photo_wall_posts FOR SELECT
  TO authenticated
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "Users can post photos"
  ON photo_wall_posts FOR INSERT
  TO authenticated
  WITH CHECK (author_id = auth.uid());

CREATE POLICY "Authors or admins can delete photos"
  ON photo_wall_posts FOR DELETE
  TO authenticated
  USING (author_id = auth.uid() OR private.admin_can('photos', 'delete'));

-- Photo Wall Likes
CREATE TABLE IF NOT EXISTS photo_wall_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photo_id uuid NOT NULL REFERENCES photo_wall_posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (photo_id, user_id)
);

ALTER TABLE photo_wall_likes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can view photo likes"
  ON photo_wall_likes FOR SELECT
  TO authenticated
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "Users can like photos"
  ON photo_wall_likes FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can unlike photos"
  ON photo_wall_likes FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

-- Pet Profiles
CREATE TABLE IF NOT EXISTS pet_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users(id),
  name text NOT NULL,
  species text NOT NULL DEFAULT 'dog',
  breed text NOT NULL DEFAULT '',
  photo_url text NOT NULL DEFAULT '',
  fun_fact text NOT NULL DEFAULT '',
  likes_count int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE pet_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can view pets"
  ON pet_profiles FOR SELECT
  TO authenticated
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "Users can add pets"
  ON pet_profiles FOR INSERT
  TO authenticated
  WITH CHECK (owner_id = auth.uid());

CREATE POLICY "Users can update own pets"
  ON pet_profiles FOR UPDATE
  TO authenticated
  USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());

CREATE POLICY "Users can delete own pets"
  ON pet_profiles FOR DELETE
  TO authenticated
  USING (owner_id = auth.uid());

-- Pet Likes
CREATE TABLE IF NOT EXISTS pet_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pet_id uuid NOT NULL REFERENCES pet_profiles(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pet_id, user_id)
);

ALTER TABLE pet_likes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can view pet likes"
  ON pet_likes FOR SELECT
  TO authenticated
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "Users can like pets"
  ON pet_likes FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can unlike pets"
  ON pet_likes FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

-- Playlist Weeks
CREATE TABLE IF NOT EXISTS playlist_weeks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  week_start date NOT NULL UNIQUE,
  theme text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE playlist_weeks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can view playlists"
  ON playlist_weeks FOR SELECT
  TO authenticated
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "Admins can manage playlist weeks"
  ON playlist_weeks FOR INSERT
  TO authenticated
  WITH CHECK (private.admin_can('playlists', 'create'));

CREATE POLICY "Admins can update playlist weeks"
  ON playlist_weeks FOR UPDATE
  TO authenticated
  USING (private.admin_can('playlists', 'update'))
  WITH CHECK (private.admin_can('playlists', 'update'));

-- Playlist Songs
CREATE TABLE IF NOT EXISTS playlist_songs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  playlist_id uuid NOT NULL REFERENCES playlist_weeks(id) ON DELETE CASCADE,
  submitted_by uuid NOT NULL REFERENCES auth.users(id),
  title text NOT NULL,
  artist text NOT NULL,
  url text,
  votes int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE playlist_songs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can view songs"
  ON playlist_songs FOR SELECT
  TO authenticated
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "Users can submit songs"
  ON playlist_songs FOR INSERT
  TO authenticated
  WITH CHECK (submitted_by = auth.uid());

CREATE POLICY "Users can delete own songs"
  ON playlist_songs FOR DELETE
  TO authenticated
  USING (submitted_by = auth.uid());

-- Playlist Votes
CREATE TABLE IF NOT EXISTS playlist_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  song_id uuid NOT NULL REFERENCES playlist_songs(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (song_id, user_id)
);

ALTER TABLE playlist_votes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can view playlist votes"
  ON playlist_votes FOR SELECT
  TO authenticated
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "Users can vote on songs"
  ON playlist_votes FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can remove song votes"
  ON playlist_votes FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

-- Trigger: update upvote count on leadership questions
CREATE OR REPLACE FUNCTION public.update_leadership_question_votes()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE leadership_questions SET upvotes = upvotes + 1 WHERE id = NEW.question_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE leadership_questions SET upvotes = upvotes - 1 WHERE id = OLD.question_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER trg_leadership_question_votes
  AFTER INSERT OR DELETE ON leadership_question_votes
  FOR EACH ROW EXECUTE FUNCTION public.update_leadership_question_votes();

-- Trigger: update likes count on photo wall posts
CREATE OR REPLACE FUNCTION public.update_photo_wall_likes()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE photo_wall_posts SET likes_count = likes_count + 1 WHERE id = NEW.photo_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE photo_wall_posts SET likes_count = likes_count - 1 WHERE id = OLD.photo_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER trg_photo_wall_likes
  AFTER INSERT OR DELETE ON photo_wall_likes
  FOR EACH ROW EXECUTE FUNCTION public.update_photo_wall_likes();

-- Trigger: update likes count on pet profiles
CREATE OR REPLACE FUNCTION public.update_pet_likes()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE pet_profiles SET likes_count = likes_count + 1 WHERE id = NEW.pet_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE pet_profiles SET likes_count = likes_count - 1 WHERE id = OLD.pet_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER trg_pet_likes
  AFTER INSERT OR DELETE ON pet_likes
  FOR EACH ROW EXECUTE FUNCTION public.update_pet_likes();

-- Trigger: update votes count on playlist songs
CREATE OR REPLACE FUNCTION public.update_playlist_votes()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE playlist_songs SET votes = votes + 1 WHERE id = NEW.song_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE playlist_songs SET votes = votes - 1 WHERE id = OLD.song_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER trg_playlist_votes
  AFTER INSERT OR DELETE ON playlist_votes
  FOR EACH ROW EXECUTE FUNCTION public.update_playlist_votes();

-- Restrict trigger functions
REVOKE ALL ON FUNCTION public.update_leadership_question_votes() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_leadership_question_votes() TO authenticated;

REVOKE ALL ON FUNCTION public.update_photo_wall_likes() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_photo_wall_likes() TO authenticated;

REVOKE ALL ON FUNCTION public.update_pet_likes() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_pet_likes() TO authenticated;

REVOKE ALL ON FUNCTION public.update_playlist_votes() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_playlist_votes() TO authenticated;
