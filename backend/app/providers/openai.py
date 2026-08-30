"""OpenAI Responses API adapter used by every ReadSync generation prompt."""

import json
import logging

import httpx

from app.config import settings

log = logging.getLogger("openai_provider")

RESPONSES_URL = "https://api.openai.com/v1/responses"


class OpenAIProviderError(RuntimeError):
    pass


def generate_text(
    *, instructions: str, input_text: str, max_output_tokens: int = 1_500
) -> str:
    """Generate text with the centrally configured model and reasoning effort."""
    if not settings.openai_api_key:
        raise OpenAIProviderError("OPENAI_API_KEY is not configured")

    try:
        response = httpx.post(
            RESPONSES_URL,
            headers={
                "Authorization": f"Bearer {settings.openai_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": settings.openai_model,
                "reasoning": {"effort": settings.openai_reasoning_effort},
                "instructions": instructions,
                "input": input_text,
                "max_output_tokens": max_output_tokens,
                # Book excerpts and personal notes should not be retained by the
                # provider merely to produce an in-app summary.
                "store": False,
            },
            timeout=90,
        )
        response.raise_for_status()
        payload = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        log.error("OpenAI Responses request failed: %s", exc)
        raise OpenAIProviderError("OpenAI generation failed") from exc

    parts: list[str] = []
    for item in payload.get("output", []):
        if item.get("type") != "message":
            continue
        for content in item.get("content", []):
            if content.get("type") == "output_text" and content.get("text"):
                parts.append(content["text"])
    text = "\n".join(parts).strip()
    if not text:
        raise OpenAIProviderError("OpenAI returned no text")
    return text


def generate_json(
    *, instructions: str, input_text: str, schema_name: str, schema: dict,
    max_output_tokens: int = 4_000,
) -> dict:
    """Generate provider-validated JSON using the Responses structured output API."""
    if not settings.openai_api_key:
        raise OpenAIProviderError("OPENAI_API_KEY is not configured")
    try:
        response = httpx.post(
            RESPONSES_URL,
            headers={
                "Authorization": f"Bearer {settings.openai_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": settings.openai_model,
                "reasoning": {"effort": settings.openai_reasoning_effort},
                "instructions": instructions,
                "input": input_text,
                "max_output_tokens": max_output_tokens,
                "text": {"format": {
                    "type": "json_schema", "name": schema_name,
                    "strict": True, "schema": schema,
                }},
                "store": False,
            },
            timeout=90,
        )
        response.raise_for_status()
        payload = response.json()
        parts = [
            content["text"]
            for item in payload.get("output", []) if item.get("type") == "message"
            for content in item.get("content", [])
            if content.get("type") == "output_text" and content.get("text")
        ]
        result = json.loads("\n".join(parts))
    except (httpx.HTTPError, ValueError, KeyError, TypeError) as exc:
        log.error("OpenAI structured generation failed: %s", exc)
        raise OpenAIProviderError("OpenAI structured generation failed") from exc
    if not isinstance(result, dict):
        raise OpenAIProviderError("OpenAI returned invalid structured output")
    return result
