"""Apply Inkflow SQL migrations to the configured Neon database in order."""

from __future__ import annotations

import os
from pathlib import Path

import psycopg


def main() -> None:
    database_url = os.getenv("DATABASE_URL", "").strip()
    if not database_url:
        raise SystemExit("DATABASE_URL is required")

    migration_dir = Path(__file__).resolve().parents[2] / "services" / "db" / "migrations"
    files = sorted(migration_dir.glob("*.sql"))
    if not files:
        raise SystemExit(f"No SQL migrations found in {migration_dir}")

    with psycopg.connect(database_url) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS schema_migrations (
                  filename TEXT PRIMARY KEY,
                  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
                )
                """
            )
            cursor.execute("SELECT filename FROM schema_migrations")
            applied = {row[0] for row in cursor.fetchall()}
            for file in files:
                if file.name in applied:
                    print(f"skip {file.name}")
                    continue
                cursor.execute(file.read_text())
                cursor.execute(
                    "INSERT INTO schema_migrations (filename) VALUES (%s)",
                    (file.name,),
                )
                print(f"applied {file.name}")
        connection.commit()


if __name__ == "__main__":
    main()
