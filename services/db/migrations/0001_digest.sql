-- Daily-digest sync tables for ReadSync.
-- Replaces the legacy Supabase tables. All rows are owner-scoped to the
-- authenticated Better Auth subject; the iOS app sets owner_id to the signed-in
-- user id, and RLS enforces that it matches the JWT subject.

-- Subscriber preferences: one row per user (email + enabled flag).
CREATE TABLE IF NOT EXISTS digest_subscribers (
  owner_id   TEXT PRIMARY KEY,
  email      TEXT NOT NULL,
  enabled    BOOLEAN NOT NULL DEFAULT false,
  last_sent_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE digest_subscribers ENABLE ROW LEVEL SECURITY;

CREATE POLICY digest_subscribers_select ON digest_subscribers
  FOR SELECT USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY digest_subscribers_insert ON digest_subscribers
  FOR INSERT WITH CHECK (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY digest_subscribers_update ON digest_subscribers
  FOR UPDATE USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  ) WITH CHECK (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY digest_subscribers_delete ON digest_subscribers
  FOR DELETE USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );

-- Mirrored highlights + notes that feed the digest email.
CREATE TABLE IF NOT EXISTS digest_notes (
  id         TEXT PRIMARY KEY,
  owner_id   TEXT NOT NULL,
  kind       TEXT NOT NULL,
  book_title TEXT NOT NULL DEFAULT '',
  chapter    TEXT NOT NULL DEFAULT '',
  passage    TEXT NOT NULL DEFAULT '',
  body       TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE digest_notes ENABLE ROW LEVEL SECURITY;

CREATE POLICY digest_notes_select ON digest_notes
  FOR SELECT USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY digest_notes_insert ON digest_notes
  FOR INSERT WITH CHECK (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY digest_notes_update ON digest_notes
  FOR UPDATE USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  ) WITH CHECK (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY digest_notes_delete ON digest_notes
  FOR DELETE USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );

-- Active books used for the AI study-note fallback when no notes exist.
CREATE TABLE IF NOT EXISTS digest_books (
  id         TEXT PRIMARY KEY,
  owner_id   TEXT NOT NULL,
  title      TEXT NOT NULL DEFAULT '',
  author     TEXT NOT NULL DEFAULT '',
  excerpt    TEXT NOT NULL DEFAULT '',
  is_active  BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE digest_books ENABLE ROW LEVEL SECURITY;

CREATE POLICY digest_books_select ON digest_books
  FOR SELECT USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY digest_books_insert ON digest_books
  FOR INSERT WITH CHECK (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY digest_books_update ON digest_books
  FOR UPDATE USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  ) WITH CHECK (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY digest_books_delete ON digest_books
  FOR DELETE USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
