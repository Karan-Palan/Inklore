-- Durable, installation-scoped chapter video jobs.
CREATE TABLE IF NOT EXISTS video_summary_jobs (
  id UUID PRIMARY KEY,
  owner_id TEXT NOT NULL,
  book_id TEXT NOT NULL,
  book_title TEXT NOT NULL,
  author TEXT NOT NULL DEFAULT '',
  chapter_id TEXT NOT NULL,
  chapter_title TEXT NOT NULL,
  source_text TEXT,
  status TEXT NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'planning', 'rendering', 'completed', 'failed')),
  aspect_ratio TEXT CHECK (aspect_ratio IN ('9:16', '16:9')),
  title TEXT,
  visual_style TEXT,
  duration_seconds INTEGER,
  error_message TEXT,
  provider_status_code INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS video_summary_jobs_worker_idx
  ON video_summary_jobs (status, updated_at);
CREATE INDEX IF NOT EXISTS video_summary_jobs_owner_chapter_idx
  ON video_summary_jobs (owner_id, book_id, chapter_id, created_at DESC);

CREATE TABLE IF NOT EXISTS video_summary_scenes (
  id UUID PRIMARY KEY,
  job_id UUID NOT NULL REFERENCES video_summary_jobs(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  title TEXT NOT NULL,
  narration TEXT NOT NULL,
  visual_prompt TEXT NOT NULL,
  source_evidence TEXT NOT NULL,
  duration_seconds INTEGER NOT NULL CHECK (duration_seconds IN (4, 6, 8)),
  provider_generation_id TEXT UNIQUE,
  status TEXT NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'submitted', 'generating', 'completed', 'failed')),
  content_url TEXT,
  content_mime_type TEXT,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(job_id, position)
);

CREATE INDEX IF NOT EXISTS video_summary_scenes_job_idx
  ON video_summary_scenes (job_id, position);
