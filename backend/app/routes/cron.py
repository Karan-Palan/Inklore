"""Vercel cron entry points protected by a server-side shared secret."""
from __future__ import annotations

import hmac

from fastapi import APIRouter, Header, HTTPException, status

from app import digest
from app.config import settings
from app.jobs.video_summary_job import run_once

router = APIRouter(prefix="/api/cron", tags=["cron"])


def _authorize(authorization: str | None = Header(default=None)) -> None:
    secret = settings.cron_secret
    expected = f"Bearer {secret}"
    if not secret or not authorization or not hmac.compare_digest(authorization, expected):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized cron")


@router.get("/digests")
def run_digests(authorization: str | None = Header(default=None)) -> dict[str, int]:
    _authorize(authorization)
    return digest.run_due()


@router.get("/video-worker")
def run_video_worker(authorization: str | None = Header(default=None)) -> dict[str, int]:
    _authorize(authorization)
    return run_once()
