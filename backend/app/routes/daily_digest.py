"""Daily-digest routes — sync preferences/content and trigger sends.

All database writes happen here, server-side, because the managed data REST API
is read-only for these tables. The iOS app posts its local highlights/notes and
active books with each call.
"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app import digest
from app.tenx_auth import current_user

router = APIRouter()


class NotePayload(BaseModel):
    id: str
    kind: str = "note"
    book_title: str = ""
    chapter: str = ""
    passage: str = ""
    body: str = ""
    created_at: str | None = None


class BookPayload(BaseModel):
    id: str
    title: str = ""
    author: str = ""
    excerpt: str = ""


class DigestRequest(BaseModel):
    email: str | None = None
    enabled: bool = True
    force: bool = False
    notes: list[NotePayload] = Field(default_factory=list)
    books: list[BookPayload] = Field(default_factory=list)


class PreferencesRequest(BaseModel):
    email: str
    enabled: bool = False


class DigestResponse(BaseModel):
    sent: bool
    reason: str


class OKResponse(BaseModel):
    ok: bool = True


@router.post("/api/v1/digest/preferences", response_model=OKResponse)
def save_preferences(
    payload: PreferencesRequest, claims: dict = Depends(current_user)
) -> OKResponse:
    owner_id = claims["sub"]
    digest.upsert_subscriber(owner_id, payload.email, payload.enabled)
    return OKResponse()


@router.post("/api/v1/daily-digest", response_model=DigestResponse)
def trigger_digest(
    payload: DigestRequest, claims: dict = Depends(current_user)
) -> DigestResponse:
    owner_id = claims["sub"]

    # The app sends current data with the request; persist it server-side.
    if payload.email:
        digest.upsert_subscriber(owner_id, payload.email, payload.enabled)
    digest.replace_notes(owner_id, [n.model_dump() for n in payload.notes])
    digest.replace_books(owner_id, [b.model_dump() for b in payload.books])

    subscriber = digest.fetch_subscriber(owner_id)
    if not subscriber:
        raise HTTPException(status_code=404, detail="no digest subscription found")
    result = digest.run_for_subscriber(subscriber, force=payload.force)
    return DigestResponse(sent=result["sent"], reason=result["reason"])
