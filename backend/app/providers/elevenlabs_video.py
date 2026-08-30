"""Server-owned adapter for ElevenLabs' asynchronous video flow API."""
from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any

import httpx

from app.config import settings

log = logging.getLogger("elevenlabs_video_provider")
BASE_URL = "https://api.elevenlabs.io/v1/flows/video"


@dataclass
class ElevenLabsVideoError(RuntimeError):
    message: str
    status_code: int | None = None

    def __str__(self) -> str:
        return self.message


def _error_message(response: httpx.Response, fallback: str) -> str:
    try:
        payload = response.json()
        detail = payload.get("detail") or payload.get("message") or payload.get("error")
        if isinstance(detail, dict):
            detail = detail.get("message") or detail.get("status")
        if detail:
            return str(detail)
    except (ValueError, TypeError):
        pass
    return fallback


def create_video(*, prompt: str, duration_secs: int, aspect_ratio: str) -> dict[str, Any]:
    if not settings.elevenlabs_api_key:
        raise ElevenLabsVideoError("Video generation is not configured")
    model = settings.elevenlabs_video_model
    duration = min((4, 6, 8), key=lambda candidate: abs(candidate - duration_secs))
    body: dict[str, Any] = {
        "model_id": model,
        "prompt": prompt,
        "aspect_ratio": aspect_ratio,
        "duration_secs": duration,
        "generate_audio": True,
    }
    if model.startswith("bytedance-seedance"):
        body["resolution"] = (
            "1080p" if settings.elevenlabs_video_resolution == "4K"
            else settings.elevenlabs_video_resolution
        )
    else:
        body["resolution"] = settings.elevenlabs_video_resolution
        body["enhance_prompt"] = True
    try:
        response = httpx.post(
            BASE_URL,
            headers={
                "xi-api-key": settings.elevenlabs_api_key,
                "Content-Type": "application/json",
            },
            json=body,
            timeout=30,
        )
    except httpx.HTTPError as exc:
        log.error("ElevenLabs video submission failed: %s", exc)
        raise ElevenLabsVideoError("Video service could not be reached") from exc
    if response.status_code >= 400:
        message = _error_message(response, "Video generation could not be started")
        log.warning("ElevenLabs video submission rejected (%s): %s", response.status_code, message)
        raise ElevenLabsVideoError(message, status_code=response.status_code)
    try:
        payload = response.json()
    except ValueError as exc:
        raise ElevenLabsVideoError("Video service returned an invalid response") from exc
    if not payload.get("id"):
        raise ElevenLabsVideoError("Video service returned no generation id")
    return payload


def get_video(generation_id: str) -> dict[str, Any]:
    if not settings.elevenlabs_api_key:
        raise ElevenLabsVideoError("Video generation is not configured")
    try:
        response = httpx.get(
            f"{BASE_URL}/{generation_id}",
            headers={"xi-api-key": settings.elevenlabs_api_key},
            timeout=20,
        )
    except httpx.HTTPError as exc:
        log.warning("ElevenLabs video status failed: %s", exc)
        raise ElevenLabsVideoError("Video status could not be refreshed") from exc
    if response.status_code >= 400:
        raise ElevenLabsVideoError(
            _error_message(response, "Video status could not be refreshed"),
            status_code=response.status_code,
        )
    try:
        return response.json()
    except ValueError as exc:
        raise ElevenLabsVideoError("Video service returned an invalid response") from exc
