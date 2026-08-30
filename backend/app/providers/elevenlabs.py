"""ElevenLabs narration adapter with character-level timing information."""

from __future__ import annotations

import logging
from typing import Any

import httpx

from app.config import settings

log = logging.getLogger("elevenlabs_provider")

BASE_URL = "https://api.elevenlabs.io/v1/text-to-speech"


class ElevenLabsProviderError(RuntimeError):
    pass


def narrate_with_timestamps(*, text: str, voice_id: str | None = None) -> dict[str, Any]:
    """Return base64 audio plus character timing for synchronized highlighting."""
    if not settings.elevenlabs_api_key:
        raise ElevenLabsProviderError("ELEVENLABS_API_KEY is not configured")
    selected_voice = (voice_id or settings.elevenlabs_voice_id).strip()
    if not selected_voice:
        raise ElevenLabsProviderError("ELEVENLABS_VOICE_ID is not configured")

    body: dict[str, Any] = {"text": text}
    # Leave the provider default untouched until a model is intentionally
    # selected; once set, all requests are pinned through this one variable.
    if settings.elevenlabs_model_id:
        body["model_id"] = settings.elevenlabs_model_id

    try:
        response = httpx.post(
            f"{BASE_URL}/{selected_voice}/with-timestamps",
            params={"output_format": settings.elevenlabs_output_format},
            headers={
                "xi-api-key": settings.elevenlabs_api_key,
                "Content-Type": "application/json",
            },
            json=body,
            timeout=120,
        )
        response.raise_for_status()
        payload = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        log.error("ElevenLabs narration request failed: %s", exc)
        raise ElevenLabsProviderError("ElevenLabs narration failed") from exc

    if not payload.get("audio_base64"):
        raise ElevenLabsProviderError("ElevenLabs returned no audio")
    return payload
