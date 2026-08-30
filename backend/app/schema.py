"""Apply the small runtime schemas required by the deployed API.

Vercel deploys the backend directory as its project root, so the canonical SQL
files under services/ are not available to a serverless function. These two
packaged migrations keep a fresh production instance from accepting requests
before its video/digest tables exist.
"""

from __future__ import annotations

import logging
import os
from pathlib import Path

import psycopg

log = logging.getLogger("inkflow_schema")

_MIGRATIONS = ("0003_video_summaries.sql", "0004_digest_schedule.sql")
_LOCK_ID = 4_946_535_676  # Stable Inkflow advisory-lock namespace.


def ensure_runtime_schema() -> None:
    database_url = os.getenv("DATABASE_URL", "").strip()
    if not database_url:
        log.info("DATABASE_URL is absent; skipping runtime schema check")
        return

    sql_dir = Path(__file__).with_name("sql")
    with psycopg.connect(database_url, connect_timeout=5) as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT pg_advisory_xact_lock(%s)", (_LOCK_ID,))
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS schema_migrations (
                  filename TEXT PRIMARY KEY,
                  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
                )
                """
            )
            cursor.execute(
                "SELECT filename FROM schema_migrations WHERE filename = ANY(%s)",
                (list(_MIGRATIONS),),
            )
            applied = {row[0] for row in cursor.fetchall()}
            for filename in _MIGRATIONS:
                if filename in applied:
                    continue
                cursor.execute((sql_dir / filename).read_text())
                cursor.execute(
                    "INSERT INTO schema_migrations (filename) VALUES (%s)",
                    (filename,),
                )
                log.info("Applied %s", filename)
        connection.commit()


def ensure_runtime_schema_safely() -> None:
    try:
        ensure_runtime_schema()
    except Exception:
        # Search, import, and narration must remain available if Neon is waking
        # or temporarily unavailable. Database-backed endpoints will surface a
        # normal request error and the next cold start retries the migration.
        log.exception("Runtime schema check failed")
