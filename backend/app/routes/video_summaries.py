"""Authenticated, non-blocking API for long-running book video summaries."""

from __future__ import annotations

from typing import Literal
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.db import execute, query
from app.tenx_auth import current_user

router = APIRouter(prefix="/api/v1/video-summaries", tags=["video summaries"])


class CreateVideoRequest(BaseModel):
    book_id: str = Field(min_length=1, max_length=200)
    book_title: str = Field(min_length=1, max_length=300)
    author: str = Field(default="", max_length=300)
    text: str = Field(min_length=200, max_length=200_000)


class SceneResponse(BaseModel):
    position: int
    title: str
    narration: str
    duration_seconds: int
    status: str
    content_url: str | None = None


class VideoJobResponse(BaseModel):
    id: UUID
    status: Literal["queued", "planning", "rendering", "completed", "failed"]
    title: str | None = None
    aspect_ratio: Literal["9:16", "16:9"] | None = None
    duration_seconds: int | None = None
    completed_scenes: int = 0
    total_scenes: int = 0
    error_message: str | None = None
    scenes: list[SceneResponse] = Field(default_factory=list)


def _response(job: dict, scenes: list[dict]) -> VideoJobResponse:
    return VideoJobResponse(
        id=job["id"], status=job["status"], title=job.get("title"),
        aspect_ratio=job.get("aspect_ratio"), duration_seconds=job.get("duration_seconds"),
        error_message=job.get("error_message"), total_scenes=len(scenes),
        completed_scenes=sum(scene["status"] == "completed" for scene in scenes),
        scenes=[SceneResponse(**scene) for scene in scenes],
    )


@router.post("", response_model=VideoJobResponse, status_code=status.HTTP_202_ACCEPTED)
def create_video_summary(
    payload: CreateVideoRequest, claims: dict = Depends(current_user)
) -> VideoJobResponse:
    active = query(
        """SELECT * FROM video_summary_jobs
           WHERE owner_id=%s AND book_id=%s
             AND status IN ('queued','planning','rendering')
           ORDER BY created_at DESC LIMIT 1""",
        (claims["sub"], payload.book_id),
    )
    if active:
        scenes = query(
            """SELECT position, title, narration, duration_seconds, status, content_url
               FROM video_summary_scenes WHERE job_id=%s ORDER BY position""",
            (active[0]["id"],),
        )
        return _response(active[0], scenes)
    job_id = uuid4()
    execute(
        """
        INSERT INTO video_summary_jobs
          (id, owner_id, book_id, book_title, author, source_text)
        VALUES (%s, %s, %s, %s, %s, %s)
        """,
        (job_id, claims["sub"], payload.book_id, payload.book_title,
         payload.author, payload.text),
    )
    return VideoJobResponse(id=job_id, status="queued")


@router.get("/{job_id}", response_model=VideoJobResponse)
def get_video_summary(
    job_id: UUID, claims: dict = Depends(current_user)
) -> VideoJobResponse:
    jobs = query(
        "SELECT * FROM video_summary_jobs WHERE id = %s AND owner_id = %s",
        (job_id, claims["sub"]),
    )
    if not jobs:
        raise HTTPException(status_code=404, detail="Video summary not found")
    scenes = query(
        """
        SELECT position, title, narration, duration_seconds, status, content_url
        FROM video_summary_scenes WHERE job_id = %s ORDER BY position
        """,
        (job_id,),
    )
    return _response(jobs[0], scenes)
