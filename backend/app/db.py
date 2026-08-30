"""Bounded, suspend-safe Postgres access for the 10x Free Backend.

The runtime can autosuspend between requests, so we use a short connect timeout
and validate connections on checkout instead of holding a long-lived pool that
could preserve stale sockets across resume.
"""
import os
from contextlib import contextmanager

import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

_pool: ConnectionPool | None = None


def _get_pool() -> ConnectionPool:
    global _pool
    if _pool is None:
        # Vercel + Neon use DATABASE_URL. Keep the legacy 10x name as a
        # migration fallback so the same backend can run in either environment.
        database_url = (
            os.environ.get("DATABASE_URL", "").strip()
            or os.environ.get("TENX_DATABASE_URL", "").strip()
        )
        if not database_url:
            raise RuntimeError("DATABASE_URL is not configured")
        _pool = ConnectionPool(
            conninfo=database_url,
            min_size=0,
            max_size=4,
            timeout=8,
            max_lifetime=300,
            kwargs={"connect_timeout": 5},
            check=ConnectionPool.check_connection,
            open=True,
        )
    return _pool


@contextmanager
def connection():
    pool = _get_pool()
    with pool.connection() as conn:
        conn.row_factory = dict_row
        yield conn


def query(sql: str, params: tuple = ()) -> list[dict]:
    with connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchall()


def execute(sql: str, params: tuple = ()) -> None:
    with connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
        conn.commit()
