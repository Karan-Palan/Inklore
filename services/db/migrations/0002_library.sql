-- Inkflow cloud library schema.
--
-- Mirrors the on-device SwiftData model so a signed-in reader's library,
-- highlights, notes, reading sessions, and goal can sync across devices.
-- Every table is owner-scoped to the authenticated Better Auth subject: the
-- owner_id column defaults to the JWT `sub`, RLS enforces that reads/writes
-- only touch the caller's rows, and child rows are additionally tied to a
-- parent book that the same user owns.
--
-- Owner default + policy predicate use the standard managed expression so an
-- app insert that OMITS owner_id still succeeds (the DB fills it from the JWT).

-- Reusable owner expression:
--   coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
--            nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')

-- ---------------------------------------------------------------------------
-- library_books: one row per book in the reader's library.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS library_books (
  id            TEXT PRIMARY KEY,
  owner_id      TEXT NOT NULL DEFAULT (coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')),
  title         TEXT NOT NULL DEFAULT '',
  author        TEXT NOT NULL DEFAULT '',
  book_description TEXT NOT NULL DEFAULT '',
  category      TEXT NOT NULL DEFAULT '',
  format        TEXT NOT NULL DEFAULT 'text',
  source_name   TEXT NOT NULL DEFAULT '',
  source_identifier TEXT NOT NULL DEFAULT '',
  cover_image_url TEXT NOT NULL DEFAULT '',
  -- Optional storage key for an imported PDF/EPUB uploaded to the book_files bucket.
  file_object_id TEXT,
  -- Reading progress (character offset for text, spine/scroll for epub, page for pdf).
  char_offset   INTEGER NOT NULL DEFAULT 0,
  spine_index   INTEGER NOT NULL DEFAULT 0,
  spine_count   INTEGER NOT NULL DEFAULT 0,
  chapter_scroll DOUBLE PRECISION NOT NULL DEFAULT 0,
  pdf_page_index INTEGER NOT NULL DEFAULT 0,
  pdf_page_count INTEGER NOT NULL DEFAULT 0,
  audio_position_seconds INTEGER NOT NULL DEFAULT 0,
  rating_times_thousand INTEGER NOT NULL DEFAULT 0,
  is_finished   BOOLEAN NOT NULL DEFAULT false,
  is_downloaded BOOLEAN NOT NULL DEFAULT false,
  added_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_opened_at TIMESTAMPTZ,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS library_books_owner_idx ON library_books (owner_id, updated_at DESC);

ALTER TABLE library_books ENABLE ROW LEVEL SECURITY;

CREATE POLICY library_books_select ON library_books
  FOR SELECT USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY library_books_insert ON library_books
  FOR INSERT WITH CHECK (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY library_books_update ON library_books
  FOR UPDATE USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  ) WITH CHECK (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY library_books_delete ON library_books
  FOR DELETE USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );

-- ---------------------------------------------------------------------------
-- library_highlights: highlighted passages, tied to a book the user owns.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS library_highlights (
  id            TEXT PRIMARY KEY,
  owner_id      TEXT NOT NULL DEFAULT (coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')),
  book_id       TEXT NOT NULL REFERENCES library_books(id) ON DELETE CASCADE,
  text          TEXT NOT NULL DEFAULT '',
  color_name    TEXT NOT NULL DEFAULT 'yellow',
  chapter_title TEXT NOT NULL DEFAULT '',
  start_offset  INTEGER NOT NULL DEFAULT 0,
  end_offset    INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS library_highlights_owner_idx ON library_highlights (owner_id, book_id, created_at DESC);

ALTER TABLE library_highlights ENABLE ROW LEVEL SECURITY;

CREATE POLICY library_highlights_select ON library_highlights
  FOR SELECT USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY library_highlights_insert ON library_highlights
  FOR INSERT WITH CHECK (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY library_highlights_update ON library_highlights
  FOR UPDATE USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  ) WITH CHECK (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY library_highlights_delete ON library_highlights
  FOR DELETE USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );

-- ---------------------------------------------------------------------------
-- library_notes: free-text notes attached to a passage in a book.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS library_notes (
  id            TEXT PRIMARY KEY,
  owner_id      TEXT NOT NULL DEFAULT (coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')),
  book_id       TEXT NOT NULL REFERENCES library_books(id) ON DELETE CASCADE,
  passage       TEXT NOT NULL DEFAULT '',
  body          TEXT NOT NULL DEFAULT '',
  chapter_title TEXT NOT NULL DEFAULT '',
  start_offset  INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS library_notes_owner_idx ON library_notes (owner_id, book_id, created_at DESC);

ALTER TABLE library_notes ENABLE ROW LEVEL SECURITY;

CREATE POLICY library_notes_select ON library_notes
  FOR SELECT USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY library_notes_insert ON library_notes
  FOR INSERT WITH CHECK (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY library_notes_update ON library_notes
  FOR UPDATE USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  ) WITH CHECK (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY library_notes_delete ON library_notes
  FOR DELETE USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );

-- ---------------------------------------------------------------------------
-- reading_sessions: one row per reading/listening session for the Stats screen.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reading_sessions (
  id            TEXT PRIMARY KEY,
  owner_id      TEXT NOT NULL DEFAULT (coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')),
  book_id       TEXT REFERENCES library_books(id) ON DELETE SET NULL,
  occurred_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  minutes       INTEGER NOT NULL DEFAULT 0,
  pages_read    INTEGER NOT NULL DEFAULT 0,
  was_listening BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS reading_sessions_owner_idx ON reading_sessions (owner_id, occurred_at DESC);

ALTER TABLE reading_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY reading_sessions_select ON reading_sessions
  FOR SELECT USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY reading_sessions_insert ON reading_sessions
  FOR INSERT WITH CHECK (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY reading_sessions_update ON reading_sessions
  FOR UPDATE USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  ) WITH CHECK (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY reading_sessions_delete ON reading_sessions
  FOR DELETE USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );

-- ---------------------------------------------------------------------------
-- reading_goals: single per-user profile + goal row (owner_id is the PK).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reading_goals (
  owner_id      TEXT PRIMARY KEY DEFAULT (coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')),
  display_name  TEXT NOT NULL DEFAULT 'Reader',
  weekly_minutes_target INTEGER NOT NULL DEFAULT 150,
  daily_minutes_target  INTEGER NOT NULL DEFAULT 20,
  current_streak INTEGER NOT NULL DEFAULT 0,
  longest_streak INTEGER NOT NULL DEFAULT 0,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE reading_goals ENABLE ROW LEVEL SECURITY;

CREATE POLICY reading_goals_select ON reading_goals
  FOR SELECT USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY reading_goals_insert ON reading_goals
  FOR INSERT WITH CHECK (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY reading_goals_update ON reading_goals
  FOR UPDATE USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  ) WITH CHECK (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
CREATE POLICY reading_goals_delete ON reading_goals
  FOR DELETE USING (
    owner_id = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  );
