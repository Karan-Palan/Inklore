from app.providers import elevenlabs_video


class FakeResponse:
    def __init__(self, payload: dict):
        self.payload = payload

    def raise_for_status(self) -> None:
        return None

    def json(self) -> dict:
        return self.payload


def test_create_video_uses_configured_model_and_valid_veo_duration(monkeypatch) -> None:
    monkeypatch.setenv("ELEVENLABS_API_KEY", "test-key")
    monkeypatch.setenv("ELEVENLABS_VIDEO_MODEL", "veo-3.1-fast-generate-001")
    captured = {}

    def fake_post(url, **kwargs):
        captured["url"] = url
        captured.update(kwargs)
        return FakeResponse({"id": "generation-1", "status": "pending"})

    monkeypatch.setattr(elevenlabs_video.httpx, "post", fake_post)
    result = elevenlabs_video.create_video(
        prompt="A cinematic library", duration_secs=7, aspect_ratio="9:16"
    )

    assert result["id"] == "generation-1"
    assert captured["url"].endswith("/v1/flows/video")
    assert captured["headers"]["xi-api-key"] == "test-key"
    assert captured["json"]["model_id"] == "veo-3.1-fast-generate-001"
    assert captured["json"]["duration_secs"] in {4, 6, 8}
    assert captured["json"]["aspect_ratio"] == "9:16"
