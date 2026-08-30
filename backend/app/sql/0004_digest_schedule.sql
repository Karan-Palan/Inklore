-- Account-free daily and weekly recap scheduling.
-- The production Neon integration may start completely empty, so create the
-- three base digest tables before extending them with scheduling fields.
CREATE TABLE IF NOT EXISTS digest_subscribers (
  owner_id TEXT PRIMARY KEY,
  email TEXT NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT false,
  last_sent_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS digest_notes (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  book_title TEXT NOT NULL DEFAULT '',
  chapter TEXT NOT NULL DEFAULT '',
  passage TEXT NOT NULL DEFAULT '',
  body TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS digest_books (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  author TEXT NOT NULL DEFAULT '',
  excerpt TEXT NOT NULL DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE digest_subscribers
  ADD COLUMN IF NOT EXISTS daily_enabled BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS weekly_enabled BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'UTC',
  ADD COLUMN IF NOT EXISTS last_daily_sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_weekly_sent_at TIMESTAMPTZ;

UPDATE digest_subscribers SET daily_enabled = enabled
WHERE enabled = true AND daily_enabled = false;

ALTER TABLE digest_books
  ADD COLUMN IF NOT EXISTS progress DOUBLE PRECISION NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS current_chapter TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS last_read_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS digest_activity (
  owner_id TEXT NOT NULL,
  activity_date DATE NOT NULL,
  read_minutes INTEGER NOT NULL DEFAULT 0 CHECK (read_minutes >= 0),
  listen_minutes INTEGER NOT NULL DEFAULT 0 CHECK (listen_minutes >= 0),
  pages_read INTEGER NOT NULL DEFAULT 0 CHECK (pages_read >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_id, activity_date)
);

CREATE INDEX IF NOT EXISTS digest_activity_owner_date_idx
  ON digest_activity (owner_id, activity_date DESC);
CREATE INDEX IF NOT EXISTS digest_books_recent_idx
  ON digest_books (owner_id, last_read_at DESC);
