"""Source-grounded planning contract shared by the worker and API responses."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.providers.openai import generate_json


class VideoScene(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str = Field(min_length=1, max_length=120)
    narration: str = Field(min_length=1, max_length=900)
    visual_prompt: str = Field(min_length=20, max_length=1_500)
    duration_seconds: Literal[4, 6, 8]
    source_evidence: str = Field(min_length=1, max_length=500)


class VideoPlan(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str = Field(min_length=1, max_length=200)
    aspect_ratio: Literal["9:16", "16:9"]
    visual_style: str = Field(min_length=1, max_length=300)
    scenes: list[VideoScene] = Field(min_length=4, max_length=15)

    @model_validator(mode="after")
    def validate_duration(self):
        duration = sum(scene.duration_seconds for scene in self.scenes)
        if not 30 <= duration <= 120:
            raise ValueError("planned duration must be 30 to 120 seconds")
        return self

    @property
    def duration_seconds(self) -> int:
        return sum(scene.duration_seconds for scene in self.scenes)


def plan_video(*, book_title: str, author: str, text: str) -> VideoPlan:
    """Let the model choose orientation and duration, then validate both."""
    instructions = """
You are the editorial director for ReadSync video summaries. Use only the
provided source. Choose 9:16 for intimate, character-led, mobile-friendly
stories and 16:9 for spatial, historical, conceptual, or cinematic material.
Let source complexity determine length: about 30 seconds for a short/simple
work and up to 120 seconds for a long/dense work. Build 4-15 coherent shots of
4, 6, or 8 seconds. Each narration must be concise enough to speak inside its
shot. Each visual_prompt must include its narration as a natural voice-over,
consistent visual style, concrete camera direction, and prohibit visible text,
logos, watermarks, and copyrighted character likenesses. source_evidence is a
short paraphrase grounding the shot; never invent facts or quotations.
""".strip()
    source = f"BOOK: {book_title}\nAUTHOR: {author or 'Unknown'}\n\nSOURCE TEXT\n{text}"
    payload = generate_json(
        instructions=instructions,
        input_text=source,
        schema_name="readsync_video_plan",
        schema=VideoPlan.model_json_schema(),
        max_output_tokens=7_000,
    )
    return VideoPlan.model_validate(payload)
