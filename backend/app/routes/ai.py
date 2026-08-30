"""Hackathon AI routes; provider credentials remain server-side."""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.config import settings
from app.providers.elevenlabs import (
    ElevenLabsProviderError,
    list_voices as list_elevenlabs_voices,
    narrate_with_timestamps,
)
from app.providers.openai import OpenAIProviderError, generate_text

router = APIRouter(prefix="/api/v1")


class SummaryRequest(BaseModel):
    book_title: str = Field(min_length=1, max_length=300)
    author: str = Field(default="", max_length=300)
    section_title: str = Field(min_length=1, max_length=300)
    text: str = Field(min_length=80, max_length=60_000)


class SummaryResponse(BaseModel):
    markdown: str
    model: str
    reasoning_effort: str


class NarrationRequest(BaseModel):
    # Small sentence-aware chunks keep provider latency, Vercel response size,
    # and iOS base64 decoding bounded. The player prefetches at most one next
    # chunk, so this remains seamless without sending an entire chapter.
    text: str = Field(min_length=1, max_length=1_400)
    voice_id: str | None = Field(default=None, max_length=200)


class NarrationResponse(BaseModel):
    audio_base64: str
    alignment: dict | None = None
    normalized_alignment: dict | None = None
    model: str | None = None
    voice_id: str
    output_format: str


class VoiceResponse(BaseModel):
    """Display-safe ElevenLabs voice metadata returned to the iOS picker."""

    voice_id: str
    name: str
    category: str | None = None
    description: str | None = None
    preview_url: str | None = None
    labels: dict[str, str] = Field(default_factory=dict)


class VoiceCatalogResponse(BaseModel):
    provider: Literal["elevenlabs"] = "elevenlabs"
    voices: list[VoiceResponse]


@router.get("/voices", response_model=VoiceCatalogResponse)
def get_voices() -> VoiceCatalogResponse:
    """Proxy the provider's approved voice list without exposing its API key."""
    try:
        voices = list_elevenlabs_voices()
    except ElevenLabsProviderError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return VoiceCatalogResponse(
        voices=[
            VoiceResponse(
                voice_id=voice.voice_id,
                name=voice.name,
                category=voice.category,
                description=voice.description,
                preview_url=voice.preview_url,
                labels=voice.labels,
            )
            for voice in voices
        ]
    )


@router.post("/summaries", response_model=SummaryResponse)
def create_summary(payload: SummaryRequest) -> SummaryResponse:
    """Generate one concise, source-grounded chapter summary."""
    instructions = """
You are Inkflow's rigorous reading companion. Summarize only the supplied
chapter text. Never invent facts, quotations, characters, arguments, or events.
Return exactly three Markdown paragraphs and nothing else:
1. A level-one heading that exactly matches the supplied Section title.
2. One complete, concise sentence (15–35 words) about the chapter.
3. A second complete, concise sentence (15–35 words) about the chapter.
Do not add labels, bullets, blockquotes, themes, takeaways, prefaces, or notes
about these instructions, the model, or being an AI.
""".strip()
    source = (
        f"Book: {payload.book_title}\n"
        f"Author: {payload.author or 'Unknown'}\n"
        f"Section: {payload.section_title}\n\n"
        f"SOURCE TEXT\n{payload.text}"
    )
    try:
        markdown = generate_text(
            # Luna at xhigh spends part of this budget on internal reasoning;
            # keep enough headroom to reliably emit the requested two lines.
            instructions=instructions, input_text=source, max_output_tokens=2_000
        )
    except OpenAIProviderError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return SummaryResponse(
        markdown=markdown,
        model=settings.openai_model,
        reasoning_effort=settings.openai_reasoning_effort,
    )


@router.post("/narration", response_model=NarrationResponse)
def create_narration(payload: NarrationRequest) -> NarrationResponse:
    """Generate ElevenLabs audio plus timing for synchronized highlighting."""
    selected_voice = (payload.voice_id or settings.elevenlabs_voice_id).strip()
    try:
        result = narrate_with_timestamps(text=payload.text, voice_id=selected_voice)
    except ElevenLabsProviderError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return NarrationResponse(
        audio_base64=result["audio_base64"],
        alignment=result.get("alignment"),
        normalized_alignment=result.get("normalized_alignment"),
        model=settings.elevenlabs_model_id or None,
        voice_id=selected_voice,
        output_format=settings.elevenlabs_output_format,
    )
