"""Short scheduled worker: plan queued chapter jobs and reconcile clips."""
from __future__ import annotations

import logging
from uuid import uuid4

from app.db import connection, execute, query
from app.providers.elevenlabs_video import ElevenLabsVideoError, create_video, get_video
from app.video_plan import plan_video

log = logging.getLogger("video_summary_worker")


def _fail_job(job_id, message: str, provider_status_code: int | None = None) -> None:
    execute(
        """
        UPDATE video_summary_jobs
        SET status='failed', error_message=%s, provider_status_code=%s,
            source_text=NULL, updated_at=now()
        WHERE id=%s
        """,
        (message[:500], provider_status_code, job_id),
    )


def plan_one() -> int:
    rows = query(
        """
        UPDATE video_summary_jobs SET status='planning', updated_at=now()
        WHERE id = (
            SELECT id FROM video_summary_jobs
            WHERE status='queued'
               OR (status='planning' AND updated_at < now() - interval '10 minutes')
            ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1
        )
        RETURNING *
        """
    )
    if not rows:
        return 0
    job = rows[0]
    try:
        plan = plan_video(
            book_title=job["book_title"],
            author=job["author"],
            chapter_title=job["chapter_title"],
            text=job["source_text"],
        )
        with connection() as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM video_summary_scenes WHERE job_id=%s", (job["id"],))
                for position, scene in enumerate(plan.scenes):
                    cur.execute(
                        """
                        INSERT INTO video_summary_scenes
                          (id, job_id, position, title, narration, visual_prompt,
                           source_evidence, duration_seconds)
                        VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                        """,
                        (
                            uuid4(), job["id"], position, scene.title, scene.narration,
                            scene.visual_prompt, scene.source_evidence, scene.duration_seconds,
                        ),
                    )
                cur.execute(
                    """
                    UPDATE video_summary_jobs SET status='rendering', title=%s,
                      aspect_ratio=%s, visual_style=%s, duration_seconds=%s,
                      source_text=NULL, updated_at=now() WHERE id=%s
                    """,
                    (
                        plan.title, plan.aspect_ratio, plan.visual_style,
                        plan.duration_seconds, job["id"],
                    ),
                )
            conn.commit()
    except Exception as exc:  # keep a bad request from wedging the worker
        log.exception("Video planning failed for %s", job["id"])
        _fail_job(job["id"], str(exc))
    return 1


def submit_scenes(limit: int = 2) -> int:
    """Submit a bounded batch; it fits comfortably inside a serverless cron run."""
    scenes = query(
        """
        SELECT s.*, j.aspect_ratio, j.visual_style
        FROM video_summary_scenes s JOIN video_summary_jobs j ON j.id=s.job_id
        WHERE s.status='queued' AND j.status='rendering'
        ORDER BY j.created_at, s.position LIMIT %s
        """,
        (limit,),
    )
    submitted = 0
    for scene in scenes:
        prompt = (
            f"Maintain this art direction: {scene['visual_style']}. "
            f"{scene['visual_prompt']} Voice-over narration, spoken clearly: "
            f"{scene['narration']}"
        )
        try:
            result = create_video(
                prompt=prompt,
                duration_secs=scene["duration_seconds"],
                aspect_ratio=scene["aspect_ratio"],
            )
            execute(
                """
                UPDATE video_summary_scenes SET status='submitted',
                  provider_generation_id=%s, updated_at=now() WHERE id=%s
                """,
                (result["id"], scene["id"]),
            )
            submitted += 1
        except ElevenLabsVideoError as exc:
            execute(
                """
                UPDATE video_summary_scenes SET status='failed', error_message=%s,
                updated_at=now() WHERE id=%s
                """,
                (str(exc)[:500], scene["id"]),
            )
            _fail_job(scene["job_id"], str(exc), exc.status_code)
    return submitted


def reconcile(limit: int = 20) -> int:
    scenes = query(
        """
        SELECT * FROM video_summary_scenes WHERE status IN ('submitted','generating')
        ORDER BY updated_at LIMIT %s
        """,
        (limit,),
    )
    updated_jobs: set = set()
    for scene in scenes:
        try:
            result = get_video(scene["provider_generation_id"])
        except ElevenLabsVideoError as exc:
            if exc.status_code in {401, 402, 403}:
                _fail_job(scene["job_id"], str(exc), exc.status_code)
            continue
        provider_status = result.get("status")
        scene_status = "generating" if provider_status in {"pending", "generating"} else provider_status
        if scene_status not in {"generating", "completed", "failed"}:
            continue
        execute(
            """
            UPDATE video_summary_scenes SET status=%s, content_url=%s,
               content_mime_type=%s, error_message=%s, updated_at=now() WHERE id=%s
            """,
            (
                scene_status, result.get("content_url"), result.get("content_mime_type"),
                result.get("error_message") or result.get("failure_reason"), scene["id"],
            ),
        )
        updated_jobs.add(scene["job_id"])
    for job_id in updated_jobs:
        counts = query(
            """
            SELECT count(*) total,
              count(*) FILTER (WHERE status='completed') completed,
              count(*) FILTER (WHERE status='failed') failed
            FROM video_summary_scenes WHERE job_id=%s
            """,
            (job_id,),
        )[0]
        if counts["failed"]:
            _fail_job(job_id, "One or more video scenes failed to render")
        elif counts["total"] and counts["completed"] == counts["total"]:
            execute(
                """
                UPDATE video_summary_jobs SET status='completed', completed_at=now(),
                updated_at=now() WHERE id=%s
                """,
                (job_id,),
            )
    return len(scenes)


def run_once() -> dict[str, int]:
    return {"planned": plan_one(), "submitted": submit_scenes(), "reconciled": reconcile()}


def run_safely() -> dict[str, int]:
    """Keep a failed opportunistic worker from breaking the HTTP response."""
    try:
        return run_once()
    except Exception:
        log.exception("Opportunistic video worker failed")
        return {"planned": 0, "submitted": 0, "reconciled": 0}


def main() -> None:
    result = run_once()
    log.info("video summary worker: %s", result)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    main()
