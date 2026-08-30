from app.providers import elevenlabs, openai
from app.routes import ai
import pytest
from pydantic import ValidationError


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


def test_summary_route_requests_only_a_heading_and_two_sentences(monkeypatch) -> None:
    captured: dict = {}

    def fake_generate_text(**kwargs):
        captured.update(kwargs)
        return "# Chapter One\n\nA concise first sentence.\n\nA concise second sentence."

    monkeypatch.setattr(ai, "generate_text", fake_generate_text)
    response = ai.create_summary(
        ai.SummaryRequest(
            book_title="A Study in Scarlet",
            author="Arthur Conan Doyle",
            section_title="Chapter One",
            text="The chapter source contains enough grounded detail to satisfy the API's minimum text length.",
        )
    )

    assert response.markdown.count("\n\n") == 2
    assert captured["max_output_tokens"] == 2_000
    assert "exactly three Markdown paragraphs" in captured["instructions"]
    assert "bullets" in captured["instructions"]
    assert "Scope:" not in captured["input_text"]


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
    assert captured["json"]["model_id"] == "eleven_multilingual_v2"


def test_narration_is_bounded_to_a_fast_mobile_chunk() -> None:
    assert len(ai.NarrationRequest(text="x" * 1_400).text) == 1_400
    with pytest.raises(ValidationError):
        ai.NarrationRequest(text="x" * 1_401)


def test_elevenlabs_reuses_an_identical_short_chunk(monkeypatch) -> None:
    monkeypatch.setenv("ELEVENLABS_API_KEY", "cache-test-key")
    monkeypatch.setenv("ELEVENLABS_VOICE_ID", "cache-voice")
    calls = 0

    def fake_post(url, **kwargs):
        nonlocal calls
        calls += 1
        return FakeResponse({"audio_base64": "bXAz"})

    monkeypatch.setattr(elevenlabs.httpx, "post", fake_post)
    first = elevenlabs.narrate_with_timestamps(text="A short cached paragraph.")
    second = elevenlabs.narrate_with_timestamps(text="A short cached paragraph.")

    assert first == second
    assert calls == 1


def test_elevenlabs_lists_voices_from_v2_without_exposing_provider_fields(monkeypatch) -> None:
    monkeypatch.setenv("ELEVENLABS_API_KEY", "test-eleven-key")
    captured: dict = {}

    def fake_get(url, **kwargs):
        captured["url"] = url
        captured.update(kwargs)
        return FakeResponse(
            {
                "voices": [
                    {
                        "voice_id": "voice-z",
                        "name": "Zora",
                        "category": "premade",
                        "description": "Warm and expressive",
                        "preview_url": "https://cdn.example/preview.mp3",
                        "labels": {"gender": "female", "accent": "British"},
                        "private_provider_field": "must not leave the provider",
                    },
                    {"voice_id": "voice-a", "name": "Ari", "labels": {}},
                    {"voice_id": "", "name": "Invalid"},
                ]
            }
        )

    monkeypatch.setattr(elevenlabs.httpx, "get", fake_get)
    voices = elevenlabs.list_voices()

    assert captured["url"].endswith("/v2/voices")
    assert captured["headers"]["xi-api-key"] == "test-eleven-key"
    assert captured["params"]["page_size"] == 100
    assert captured["params"]["include_total_count"] == "false"
    assert [voice.name for voice in voices] == ["Ari", "Zora"]
    assert voices[1].preview_url == "https://cdn.example/preview.mp3"
    assert not hasattr(voices[1], "private_provider_field")


def test_voice_route_returns_display_safe_catalogue(monkeypatch) -> None:
    monkeypatch.setattr(
        ai,
        "list_elevenlabs_voices",
        lambda: [
            elevenlabs.ElevenLabsVoice(
                voice_id="voice-123",
                name="Riley",
                category="premade",
                description="Clear and calm",
                preview_url="https://cdn.example/riley.mp3",
                labels={"accent": "American"},
            )
        ],
    )

    response = ai.get_voices()

    assert response.provider == "elevenlabs"
    assert response.voices[0].model_dump() == {
        "voice_id": "voice-123",
        "name": "Riley",
        "category": "premade",
        "description": "Clear and calm",
        "preview_url": "https://cdn.example/riley.mp3",
        "labels": {"accent": "American"},
    }
