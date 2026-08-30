"""One server-owned source of truth for provider and runtime settings."""

import os


class Settings:
    @property
    def openai_api_key(self) -> str:
        return os.getenv("OPENAI_API_KEY", "").strip()

    @property
    def openai_model(self) -> str:
        return os.getenv("OPENAI_MODEL", "gpt-5.6-luna").strip() or "gpt-5.6-luna"

    @property
    def openai_reasoning_effort(self) -> str:
        value = os.getenv("OPENAI_REASONING_EFFORT", "xhigh").strip().lower()
        allowed = {"none", "low", "medium", "high", "xhigh", "max"}
        return value if value in allowed else "xhigh"

    @property
    def elevenlabs_api_key(self) -> str:
        return os.getenv("ELEVENLABS_API_KEY", "").strip()

    @property
    def elevenlabs_model_id(self) -> str:
        return os.getenv("ELEVENLABS_MODEL_ID", "").strip()

    @property
    def elevenlabs_voice_id(self) -> str:
        return os.getenv("ELEVENLABS_VOICE_ID", "").strip()

    @property
    def elevenlabs_output_format(self) -> str:
        return (
            os.getenv("ELEVENLABS_OUTPUT_FORMAT", "mp3_44100_128").strip()
            or "mp3_44100_128"
        )

    @property
    def elevenlabs_video_model(self) -> str:
        return (
            os.getenv("ELEVENLABS_VIDEO_MODEL", "veo-3.1-fast-generate-001").strip()
            or "veo-3.1-fast-generate-001"
        )

    @property
    def elevenlabs_video_resolution(self) -> str:
        value = os.getenv("ELEVENLABS_VIDEO_RESOLUTION", "720p").strip()
        return value if value in {"720p", "1080p", "4K"} else "720p"

    @property
    def resend_api_key(self) -> str:
        return os.getenv("RESEND_API_KEY", "").strip()

    @property
    def digest_from_email(self) -> str:
        return os.getenv(
            "DIGEST_FROM_EMAIL", "ReadSync <digest@readsync.app>"
        ).strip()


settings = Settings()
