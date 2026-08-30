"""ElevenLabs voice-catalog and narration adapters.

Provider credentials stay in this module's server-only configuration path. The
mobile client receives a deliberately small, display-safe catalogue and calls
Inkflow's backend rather than ElevenLabs directly.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from collections import OrderedDict
from threading import Lock
from typing import Any

import httpx

from app.config import settings

log = logging.getLogger("elevenlabs_provider")

API_BASE_URL = "https://api.elevenlabs.io"
TTS_BASE_URL = f"{API_BASE_URL}/v1/text-to-speech"
VOICES_URL = f"{API_BASE_URL}/v2/voices"

# Re-seeks and app hand-offs often request the same short paragraph again. A
# small server-side LRU prevents duplicate provider calls across a listener's
# devices/retries while keeping large base64 responses bounded in memory.
_NARRATION_CACHE_LIMIT = 12
_narration_cache: OrderedDict[tuple[str, str, str, str], dict[str, Any]] = OrderedDict()
_narration_cache_lock = Lock()


class ElevenLabsProviderError(RuntimeError):
    pass


@dataclass(frozen=True)
class ElevenLabsVoice:
    """The safe subset of an ElevenLabs voice needed by a client picker."""

    voice_id: str
    name: str
    category: str | None
    description: str | None
    preview_url: str | None
    labels: dict[str, str]

    @classmethod
    def from_payload(cls, payload: dict[str, Any]) -> "ElevenLabsVoice | None":
        voice_id = str(payload.get("voice_id") or "").strip()
        name = str(payload.get("name") or "").strip()
        if not voice_id or not name:
            return None
        raw_labels = payload.get("labels")
        labels = (
            {str(key): str(value) for key, value in raw_labels.items() if value is not None}
            if isinstance(raw_labels, dict)
            else {}
        )
        category = str(payload["category"]).strip() if payload.get("category") else None
        description = (
            str(payload["description"]).strip() if payload.get("description") else None
        )
        preview_url = (
            str(payload["preview_url"]).strip() if payload.get("preview_url") else None
        )
        return cls(
            voice_id=voice_id,
            name=name,
            category=category or None,
            description=description or None,
            preview_url=preview_url or None,
            labels=labels,
        )


def list_voices() -> list[ElevenLabsVoice]:
    """List voices via ElevenLabs' current ``GET /v2/voices`` endpoint."""
    if not settings.elevenlabs_api_key:
        raise ElevenLabsProviderError("ELEVENLABS_API_KEY is not configured")

    voices: list[ElevenLabsVoice] = []
    seen_voice_ids: set[str] = set()
    params: dict[str, Any] = {
        "page_size": 100,
        "sort": "name",
        "sort_direction": "asc",
        # The picker does not display a count, and the provider documents this
        # as an avoidable live-snapshot cost.
        "include_total_count": "false",
    }
    try:
        # Page until the provider says there are no more voices. A hard cap is
        # defensive: the backend should never loop forever on a bad token.
        for _ in range(20):
            response = httpx.get(
                VOICES_URL,
                params=params,
                headers={"xi-api-key": settings.elevenlabs_api_key},
                timeout=30,
            )
            response.raise_for_status()
            payload = response.json()
            raw_voices = payload.get("voices")
            if not isinstance(raw_voices, list):
                raise ElevenLabsProviderError("ElevenLabs returned an invalid voice catalogue")
            for item in raw_voices:
                if not isinstance(item, dict):
                    continue
                voice = ElevenLabsVoice.from_payload(item)
                if voice and voice.voice_id not in seen_voice_ids:
                    seen_voice_ids.add(voice.voice_id)
                    voices.append(voice)
            next_page_token = payload.get("next_page_token")
            if not payload.get("has_more") or not isinstance(next_page_token, str):
                break
            params["next_page_token"] = next_page_token
    except (httpx.HTTPError, ValueError) as exc:
        log.error("ElevenLabs voice list request failed: %s", exc)
        raise ElevenLabsProviderError("ElevenLabs voice catalogue is unavailable") from exc
    return sorted(voices, key=lambda voice: voice.name.casefold())


def narrate_with_timestamps(*, text: str, voice_id: str | None = None) -> dict[str, Any]:
    """Return base64 audio plus character timing for synchronized highlighting."""
    if not settings.elevenlabs_api_key:
        raise ElevenLabsProviderError("ELEVENLABS_API_KEY is not configured")
    selected_voice = (voice_id or settings.elevenlabs_voice_id).strip()
    if not selected_voice:
        raise ElevenLabsProviderError("ELEVENLABS_VOICE_ID is not configured")

    cache_key = (
        selected_voice,
        settings.elevenlabs_model_id,
        settings.elevenlabs_output_format,
        text,
    )
    with _narration_cache_lock:
        cached = _narration_cache.get(cache_key)
        if cached is not None:
            _narration_cache.move_to_end(cache_key)
            return cached

    body: dict[str, Any] = {"text": text}
    # Leave the provider default untouched until a model is intentionally
    # selected; once set, all requests are pinned through this one variable.
    if settings.elevenlabs_model_id:
        body["model_id"] = settings.elevenlabs_model_id

    try:
        response = httpx.post(
            f"{TTS_BASE_URL}/{selected_voice}/with-timestamps",
            params={"output_format": settings.elevenlabs_output_format},
            headers={
                "xi-api-key": settings.elevenlabs_api_key,
                "Content-Type": "application/json",
            },
            json=body,
            # The iOS client only submits a short chunk. Fail predictably and
            # let it continue with the local narrator rather than leaving the
            # player in a permanent "Preparing" state.
            timeout=45,
        )
        response.raise_for_status()
        payload = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        log.error("ElevenLabs narration request failed: %s", exc)
        raise ElevenLabsProviderError("ElevenLabs narration failed") from exc

    if not payload.get("audio_base64"):
        raise ElevenLabsProviderError("ElevenLabs returned no audio")
    with _narration_cache_lock:
        _narration_cache[cache_key] = payload
        _narration_cache.move_to_end(cache_key)
        while len(_narration_cache) > _NARRATION_CACHE_LIMIT:
            _narration_cache.popitem(last=False)
    return payload
