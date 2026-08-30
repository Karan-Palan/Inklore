from datetime import datetime, timezone

import pytest

from app import digest
from app.identity import installation_owner
from app.providers import elevenlabs_video


class FakeResponse:
    def __init__(self, payload: dict, status_code: int = 200):
        self.payload = payload
        self.status_code = status_code
        self.text = str(payload)

    def json(self) -> dict:
        return self.payload


def test_video_uses_server_key_and_valid_veo_duration(monkeypatch) -> None:
    monkeypatch.setenv("ELEVENLABS_API_KEY", "test-key")
    monkeypatch.setenv("ELEVENLABS_VIDEO_MODEL", "veo-3.1-fast-generate-001")
    captured: dict = {}

    def fake_post(url, **kwargs):
        captured["url"] = url
        captured.update(kwargs)
        return FakeResponse({"id": "generation-1", "status": "pending"})

    monkeypatch.setattr(elevenlabs_video.httpx, "post", fake_post)
    result = elevenlabs_video.create_video(
        prompt="A cinematic explanation", duration_secs=7, aspect_ratio="9:16"
    )

    assert result["id"] == "generation-1"
    assert captured["url"].endswith("/v1/flows/video")
    assert captured["headers"]["xi-api-key"] == "test-key"
    assert captured["json"]["duration_secs"] in {4, 6, 8}
    assert captured["json"]["aspect_ratio"] == "9:16"


def test_video_preserves_provider_payment_requirement(monkeypatch) -> None:
    monkeypatch.setenv("ELEVENLABS_API_KEY", "test-key")

    monkeypatch.setattr(
        elevenlabs_video.httpx,
        "post",
        lambda *_args, **_kwargs: FakeResponse(
            {"detail": {"message": "This endpoint requires Pro plan or above"}}, 402
        ),
    )

    with pytest.raises(elevenlabs_video.ElevenLabsVideoError) as raised:
        elevenlabs_video.create_video(prompt="A visual", duration_secs=6, aspect_ratio="16:9")

    assert raised.value.status_code == 402
    assert "Pro plan" in str(raised.value)


def test_installation_identity_is_namespaced_and_rejects_bad_uuid() -> None:
    owner = installation_owner(x_inkflow_installation_id="9E04CB4D-83E1-4510-994F-9F1C2CD0B910")
    assert owner == "anon:9e04cb4d-83e1-4510-994f-9f1c2cd0b910"

    with pytest.raises(Exception) as raised:
        installation_owner(x_inkflow_installation_id="not-a-uuid")
    assert getattr(raised.value, "status_code", None) == 400


def test_due_recaps_respect_local_monday_and_frequency(monkeypatch) -> None:
    subscribers = [
        {
            "owner_id": "anon:one", "timezone": "Asia/Kolkata",
            "daily_enabled": True, "weekly_enabled": True,
        },
        {
            "owner_id": "anon:two", "timezone": "America/Los_Angeles",
            "daily_enabled": True, "weekly_enabled": True,
        },
    ]
    calls: list[tuple[str, str]] = []
    monkeypatch.setattr(digest, "fetch_enabled_subscribers", lambda: subscribers)
    monkeypatch.setattr(
        digest, "run_for_subscriber",
        lambda subscriber, kind, **_kwargs: calls.append((subscriber["owner_id"], kind)) or {"sent": True},
    )
    # Monday 08:30 in Kolkata; Los Angeles is Sunday evening.
    result = digest.run_due(datetime(2026, 8, 31, 3, 0, tzinfo=timezone.utc))

    assert result == {"daily": 1, "weekly": 1}
    assert calls == [("anon:one", "daily"), ("anon:one", "weekly")]
