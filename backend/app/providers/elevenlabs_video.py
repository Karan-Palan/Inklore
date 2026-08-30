"""Thin, server-owned adapter for ElevenLabs' asynchronous video API."""

from __future__ import annotations

import logging
from typing import Any

import httpx

from app.config import settings

log = logging.getLogger("elevenlabs_video_provider")
BASE_URL = "https://api.elevenlabs.io/v1/flows/video"


class ElevenLabsVideoError(RuntimeError):
    pass


def create_video(*, prompt: str, duration_secs: int, aspect_ratio: str) -> dict[str, Any]:
    if not settings.elevenlabs_api_key:
        raise ElevenLabsVideoError("ELEVENLABS_API_KEY is not configured")
    # Veo Fast accepts 4/6/8 second shots. Long summaries are intentionally a
    # sequence of shots; the client plays the completed clips continuously.
    model = settings.elevenlabs_video_model
    duration = min((4, 6, 8), key=lambda candidate: abs(candidate - duration_secs))
    body: dict[str, Any] = {
        "model_id": model, "prompt": prompt, "aspect_ratio": aspect_ratio,
        "duration_secs": duration, "generate_audio": True,
    }
    if model.startswith("bytedance-seedance"):
        body["resolution"] = "1080p" if settings.elevenlabs_video_resolution == "4K" else settings.elevenlabs_video_resolution
    else:
        body["resolution"] = settings.elevenlabs_video_resolution
        body["enhance_prompt"] = True
    try:
        response = httpx.post(
            BASE_URL,
            headers={"xi-api-key": settings.elevenlabs_api_key, "Content-Type": "application/json"},
            json=body,
            timeout=30,
        )
        response.raise_for_status()
        payload = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        log.error("ElevenLabs video submission failed: %s", exc)
        raise ElevenLabsVideoError("ElevenLabs video submission failed") from exc
    if not payload.get("id"):
        raise ElevenLabsVideoError("ElevenLabs returned no video generation id")
    return payload


def get_video(generation_id: str) -> dict[str, Any]:
    if not settings.elevenlabs_api_key:
        raise ElevenLabsVideoError("ELEVENLABS_API_KEY is not configured")
    try:
        response = httpx.get(
            f"{BASE_URL}/{generation_id}",
            headers={"xi-api-key": settings.elevenlabs_api_key},
            timeout=20,
        )
        response.raise_for_status()
        return response.json()
    except (httpx.HTTPError, ValueError) as exc:
        log.error("ElevenLabs video status failed: %s", exc)
        raise ElevenLabsVideoError("ElevenLabs video status failed") from exc
