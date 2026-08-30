"""Non-blocking, chapter-scoped video summary API for anonymous installations."""
from __future__ import annotations

from typing import Literal
from uuid import UUID, uuid4

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.db import execute, query
from app.identity import installation_owner
from app.jobs.video_summary_job import run_safely

router = APIRouter(prefix="/api/v1/video-summaries", tags=["video summaries"])


class CreateVideoRequest(BaseModel):
    book_id: str = Field(min_length=1, max_length=200)
    book_title: str = Field(min_length=1, max_length=300)
    author: str = Field(default="", max_length=300)
    chapter_id: str = Field(min_length=1, max_length=200)
    chapter_title: str = Field(min_length=1, max_length=300)
    text: str = Field(min_length=200, max_length=60_000)
    regenerate: bool = False


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
    chapter_id: str
    chapter_title: str
    title: str | None = None
    aspect_ratio: Literal["9:16", "16:9"] | None = None
    duration_seconds: int | None = None
    completed_scenes: int = 0
    total_scenes: int = 0
    error_message: str | None = None
    provider_status_code: int | None = None
    scenes: list[SceneResponse] = Field(default_factory=list)


def _response(job: dict, scenes: list[dict]) -> VideoJobResponse:
    return VideoJobResponse(
        id=job["id"],
        status=job["status"],
        chapter_id=job["chapter_id"],
        chapter_title=job["chapter_title"],
        title=job.get("title"),
        aspect_ratio=job.get("aspect_ratio"),
        duration_seconds=job.get("duration_seconds"),
        error_message=job.get("error_message"),
        provider_status_code=job.get("provider_status_code"),
        total_scenes=len(scenes),
        completed_scenes=sum(scene["status"] == "completed" for scene in scenes),
        scenes=[SceneResponse(**scene) for scene in scenes],
    )


def _load_job(job_id: UUID, owner_id: str) -> VideoJobResponse:
    jobs = query(
        "SELECT * FROM video_summary_jobs WHERE id = %s AND owner_id = %s",
        (job_id, owner_id),
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


@router.post("", response_model=VideoJobResponse, status_code=status.HTTP_202_ACCEPTED)
def create_video_summary(
    payload: CreateVideoRequest,
    background_tasks: BackgroundTasks,
    owner_id: str = Depends(installation_owner),
) -> VideoJobResponse:
    if not payload.regenerate:
        existing = query(
            """
            SELECT * FROM video_summary_jobs
            WHERE owner_id=%s AND book_id=%s AND chapter_id=%s
            ORDER BY created_at DESC LIMIT 1
            """,
            (owner_id, payload.book_id, payload.chapter_id),
        )
        if existing and existing[0]["status"] != "failed":
            response = _load_job(existing[0]["id"], owner_id)
            if response.status not in {"completed", "failed"}:
                background_tasks.add_task(run_safely)
            return response

    job_id = uuid4()
    execute(
        """
        INSERT INTO video_summary_jobs
          (id, owner_id, book_id, book_title, author, chapter_id, chapter_title, source_text)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            job_id,
            owner_id,
            payload.book_id,
            payload.book_title,
            payload.author,
            payload.chapter_id,
            payload.chapter_title,
            payload.text,
        ),
    )
    response = _load_job(job_id, owner_id)
    background_tasks.add_task(run_safely)
    return response


@router.get("/{job_id}", response_model=VideoJobResponse)
def get_video_summary(
    job_id: UUID,
    background_tasks: BackgroundTasks,
    owner_id: str = Depends(installation_owner),
) -> VideoJobResponse:
    response = _load_job(job_id, owner_id)
    if response.status not in {"completed", "failed"}:
        background_tasks.add_task(run_safely)
    return response
