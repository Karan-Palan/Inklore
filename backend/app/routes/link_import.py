"""Public, anonymous link-import API used by the iOS library."""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.import_link import ImportedArticle, ImportedFile, LinkImportError, import_link


router = APIRouter(prefix="/api/v1")


class LinkImportRequest(BaseModel):
    url: str = Field(min_length=8, max_length=2_048)


class LinkImportResponse(BaseModel):
    kind: Literal["article", "file"]
    title: str
    author: str | None = None
    text: str | None = None
    source_name: str
    source_url: str
    content_type: str | None = None


@router.post("/link-import", response_model=LinkImportResponse)
def create_link_import(payload: LinkImportRequest) -> LinkImportResponse:
    """Turn a public URL into article text or validate a direct book file."""
    try:
        result = import_link(payload.url)
    except LinkImportError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.message) from exc

    if isinstance(result, ImportedArticle):
        return LinkImportResponse(
            kind="article",
            title=result.title,
            author=result.author,
            text=result.text,
            source_name=result.source_name,
            source_url=result.source_url,
        )
    return LinkImportResponse(
        kind="file",
        title=result.title,
        source_name=result.source_name,
        source_url=result.source_url,
        content_type=result.content_type,
    )
