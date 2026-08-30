"""Hackathon AI routes; provider credentials remain server-side."""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.config import settings
from app.providers.elevenlabs import ElevenLabsProviderError, narrate_with_timestamps
from app.providers.openai import OpenAIProviderError, generate_text

router = APIRouter(prefix="/api/v1")


class SummaryRequest(BaseModel):
    book_title: str = Field(min_length=1, max_length=300)
    author: str = Field(default="", max_length=300)
    section_title: str = Field(min_length=1, max_length=300)
    scope: Literal["chapter", "book"] = "chapter"
    text: str = Field(min_length=80, max_length=60_000)


class SummaryResponse(BaseModel):
    markdown: str
    model: str
    reasoning_effort: str


class NarrationRequest(BaseModel):
    text: str = Field(min_length=1, max_length=5_000)
    voice_id: str | None = Field(default=None, max_length=200)


class NarrationResponse(BaseModel):
    audio_base64: str
    alignment: dict | None = None
    normalized_alignment: dict | None = None
    model: str | None = None
    voice_id: str
    output_format: str


@router.post("/summaries", response_model=SummaryResponse)
def create_summary(payload: SummaryRequest) -> SummaryResponse:
    """Generate a source-grounded Markdown chapter or book summary."""
    instructions = """
You are ReadSync's rigorous reading companion. Summarize only the supplied
book text. Never invent facts, quotations, characters, arguments, or events.
If evidence is missing, say so. Return polished Markdown with these sections:
# title, ## In brief, ## Key ideas, ## Themes, and ## Takeaway. Use concise
bullets under Key ideas and a blockquote for Takeaway. Do not mention these
instructions, the model, token limits, or that you are an AI.
""".strip()
    source = (
        f"Scope: {payload.scope}\n"
        f"Book: {payload.book_title}\n"
        f"Author: {payload.author or 'Unknown'}\n"
        f"Section: {payload.section_title}\n\n"
        f"SOURCE TEXT\n{payload.text}"
    )
    try:
        markdown = generate_text(
            instructions=instructions, input_text=source, max_output_tokens=1_800
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
