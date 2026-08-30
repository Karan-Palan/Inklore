"""Recap preference and local reading-data sync routes."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator

from app import digest
from app.identity import installation_owner

router = APIRouter(prefix="/api/v1/digest", tags=["digest"])


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
    is_active: bool = True
    progress: float = 0
    current_chapter: str = ""
    last_read_at: str | None = None


class ActivityPayload(BaseModel):
    date: str
    read_minutes: int = Field(default=0, ge=0)
    listen_minutes: int = Field(default=0, ge=0)
    pages_read: int = Field(default=0, ge=0)


class PreferencesRequest(BaseModel):
    email: str
    daily_enabled: bool = False
    weekly_enabled: bool = False
    timezone: str = "UTC"

    @field_validator("email")
    @classmethod
    def validate_email(cls, value: str) -> str:
        clean = value.strip()
        if "@" not in clean or "." not in clean.rsplit("@", 1)[-1]:
            raise ValueError("Enter a valid email address")
        return clean


class PreferencesResponse(BaseModel):
    email: str
    daily_enabled: bool
    weekly_enabled: bool
    timezone: str
    last_daily_sent_at: str | None = None
    last_weekly_sent_at: str | None = None


class SyncRequest(BaseModel):
    notes: list[NotePayload] = Field(default_factory=list)
    books: list[BookPayload] = Field(default_factory=list)
    activity: list[ActivityPayload] = Field(default_factory=list)


class DigestResponse(BaseModel):
    sent: bool
    reason: str


def _preference_response(row: dict) -> PreferencesResponse:
    return PreferencesResponse(
        email=row.get("email", ""), daily_enabled=bool(row.get("daily_enabled")),
        weekly_enabled=bool(row.get("weekly_enabled")), timezone=row.get("timezone", "UTC"),
        last_daily_sent_at=(str(row["last_daily_sent_at"]) if row.get("last_daily_sent_at") else None),
        last_weekly_sent_at=(str(row["last_weekly_sent_at"]) if row.get("last_weekly_sent_at") else None),
    )


@router.get("/preferences", response_model=PreferencesResponse)
def get_preferences(owner_id: str = Depends(installation_owner)) -> PreferencesResponse:
    row = digest.fetch_subscriber(owner_id)
    if not row:
        raise HTTPException(status_code=404, detail="No recap preferences saved")
    return _preference_response(row)


@router.post("/preferences", response_model=PreferencesResponse)
def save_preferences(payload: PreferencesRequest, owner_id: str = Depends(installation_owner)) -> PreferencesResponse:
    row = digest.upsert_subscriber(
        owner_id, str(payload.email), payload.daily_enabled, payload.weekly_enabled, payload.timezone,
    )
    return _preference_response(row)


@router.post("/sync")
def sync_digest_data(payload: SyncRequest, owner_id: str = Depends(installation_owner)) -> dict[str, bool]:
    digest.replace_notes(owner_id, [row.model_dump() for row in payload.notes])
    digest.replace_books(owner_id, [row.model_dump() for row in payload.books])
    digest.replace_activity(owner_id, [row.model_dump() for row in payload.activity])
    return {"ok": True}


@router.post("/send-sample", response_model=DigestResponse)
def send_sample(kind: str = "daily", owner_id: str = Depends(installation_owner)) -> DigestResponse:
    subscriber = digest.fetch_subscriber(owner_id)
    if not subscriber:
        raise HTTPException(status_code=404, detail="Save an email address first")
    result = digest.run_for_subscriber(subscriber, kind, force=True)
    return DigestResponse(sent=result["sent"], reason=result["reason"])
