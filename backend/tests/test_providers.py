from app.providers import elevenlabs, openai


class FakeResponse:
    def __init__(self, payload: dict):
        self.payload = payload

    def raise_for_status(self) -> None:
        return None

    def json(self) -> dict:
        return self.payload


def test_openai_uses_luna_xhigh_and_responses_api(monkeypatch) -> None:
    monkeypatch.setenv("OPENAI_API_KEY", "test-openai-key")
    monkeypatch.setenv("OPENAI_MODEL", "gpt-5.6-luna")
    monkeypatch.setenv("OPENAI_REASONING_EFFORT", "xhigh")
    captured: dict = {}

    def fake_post(url, **kwargs):
        captured["url"] = url
        captured.update(kwargs)
        return FakeResponse(
            {
                "output": [
                    {
                        "type": "message",
                        "content": [{"type": "output_text", "text": "# Summary"}],
                    }
                ]
            }
        )

    monkeypatch.setattr(openai.httpx, "post", fake_post)
    result = openai.generate_text(instructions="Grounded", input_text="Source")

    assert result == "# Summary"
    assert captured["url"].endswith("/v1/responses")
    assert captured["json"]["model"] == "gpt-5.6-luna"
    assert captured["json"]["reasoning"] == {"effort": "xhigh"}
    assert captured["json"]["store"] is False


def test_elevenlabs_uses_server_key_and_timing_endpoint(monkeypatch) -> None:
    monkeypatch.setenv("ELEVENLABS_API_KEY", "test-eleven-key")
    monkeypatch.setenv("ELEVENLABS_VOICE_ID", "voice-123")
    monkeypatch.setenv("ELEVENLABS_MODEL_ID", "")
    captured: dict = {}

    def fake_post(url, **kwargs):
        captured["url"] = url
        captured.update(kwargs)
        return FakeResponse(
            {
                "audio_base64": "bXAz",
                "alignment": {
                    "characters": ["H", "i"],
                    "character_start_times_seconds": [0, 0.1],
                    "character_end_times_seconds": [0.1, 0.2],
                },
            }
        )

    monkeypatch.setattr(elevenlabs.httpx, "post", fake_post)
    result = elevenlabs.narrate_with_timestamps(text="Hi")

    assert result["audio_base64"] == "bXAz"
    assert captured["url"].endswith("/voice-123/with-timestamps")
    assert captured["headers"]["xi-api-key"] == "test-eleven-key"
    assert "model_id" not in captured["json"]
