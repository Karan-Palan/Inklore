-- Account-free daily and weekly recap scheduling. Existing digest rows remain
-- valid; these columns add timezone-aware frequency preferences and activity.
ALTER TABLE digest_subscribers
  ADD COLUMN IF NOT EXISTS daily_enabled BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS weekly_enabled BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'UTC',
  ADD COLUMN IF NOT EXISTS last_daily_sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_weekly_sent_at TIMESTAMPTZ;

UPDATE digest_subscribers SET daily_enabled = enabled WHERE enabled = true AND daily_enabled = false;

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
