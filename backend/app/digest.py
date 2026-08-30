"""Core daily-digest logic shared by the route and the cron job.

For a given subscriber, gathers their synced highlights/notes. If they have
none, generates 5-10 study notes from their active books via OpenAI. The
resulting digest is emailed via Resend. `last_sent_at` guards against duplicate
same-day sends unless `force` is passed (the in-app "send sample now" button).
"""
import logging
from html import escape
from datetime import datetime, timezone

import httpx

log = logging.getLogger("daily_digest")

from app import db
from app.config import settings
from app.providers.openai import OpenAIProviderError, generate_text



def _today_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def fetch_subscriber(owner_id: str) -> dict | None:
    rows = db.query(
        "SELECT owner_id, email, enabled, last_sent_at "
        "FROM digest_subscribers WHERE owner_id = %s",
        (owner_id,),
    )
    return rows[0] if rows else None


def fetch_enabled_subscribers() -> list[dict]:
    return db.query(
        "SELECT owner_id, email, enabled, last_sent_at "
        "FROM digest_subscribers WHERE enabled = true"
    )


def fetch_notes(owner_id: str) -> list[dict]:
    return db.query(
        "SELECT kind, book_title, chapter, passage, body, created_at "
        "FROM digest_notes WHERE owner_id = %s ORDER BY created_at DESC LIMIT 50",
        (owner_id,),
    )


def fetch_active_books(owner_id: str) -> list[dict]:
    return db.query(
        "SELECT title, author, excerpt FROM digest_books "
        "WHERE owner_id = %s AND is_active = true LIMIT 5",
        (owner_id,),
    )


def upsert_subscriber(owner_id: str, email: str, enabled: bool) -> None:
    db.execute(
        "INSERT INTO digest_subscribers (owner_id, email, enabled, updated_at) "
        "VALUES (%s, %s, %s, now()) "
        "ON CONFLICT (owner_id) DO UPDATE SET "
        "email = EXCLUDED.email, enabled = EXCLUDED.enabled, updated_at = now()",
        (owner_id, email, enabled),
    )


def replace_notes(owner_id: str, notes: list[dict]) -> None:
    """Replace all synced notes for this owner with the provided rows."""
    with db.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM digest_notes WHERE owner_id = %s", (owner_id,))
            for n in notes[:200]:
                cur.execute(
                    "INSERT INTO digest_notes "
                    "(id, owner_id, kind, book_title, chapter, passage, body, created_at) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
                    (
                        n.get("id"),
                        owner_id,
                        n.get("kind", "note"),
                        n.get("book_title", ""),
                        n.get("chapter", ""),
                        n.get("passage", ""),
                        n.get("body", ""),
                        n.get("created_at") or datetime.now(timezone.utc).isoformat(),
                    ),
                )
        conn.commit()


def replace_books(owner_id: str, books: list[dict]) -> None:
    """Replace all synced active books for this owner with the provided rows."""
    with db.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM digest_books WHERE owner_id = %s", (owner_id,))
            for b in books[:20]:
                cur.execute(
                    "INSERT INTO digest_books "
                    "(id, owner_id, title, author, excerpt, is_active, updated_at) "
                    "VALUES (%s, %s, %s, %s, %s, true, now())",
                    (
                        b.get("id"),
                        owner_id,
                        b.get("title", ""),
                        b.get("author", ""),
                        (b.get("excerpt") or "")[:4000],
                    ),
                )
        conn.commit()


def mark_sent(owner_id: str) -> None:
    db.execute(
        "UPDATE digest_subscribers SET last_sent_at = now() WHERE owner_id = %s",
        (owner_id,),
    )


def _already_sent_today(subscriber: dict) -> bool:
    last = subscriber.get("last_sent_at")
    if not last:
        return False
    if isinstance(last, str):
        try:
            last = datetime.fromisoformat(last)
        except ValueError:
            return False
    return last.astimezone(timezone.utc).strftime("%Y-%m-%d") == _today_utc()


def _generate_study_notes(books: list[dict]) -> list[str]:
    """Generate 5-10 notes through the shared GPT-5.6 Luna configuration."""
    if not settings.openai_api_key or not books:
        return []
    book_summary = "\n\n".join(
        f"Title: {b['title']}\nAuthor: {b['author']}\nExcerpt: {b['excerpt'][:1500]}"
        for b in books
    )
    try:
        content = generate_text(
            instructions=(
                "You are a thoughtful reading companion. Given excerpts from books "
                "a reader is currently reading, write 5 to 10 concise, source-grounded "
                "study notes that help reflection and retention. Never invent details. "
                "Return each note on its own line, without numbering or Markdown."
            ),
            input_text=book_summary,
            max_output_tokens=900,
        )
    except OpenAIProviderError as exc:
        log.error("OpenAI study-note generation failed: %s", exc)
        return []
    return [line.strip("-• ").strip() for line in content.splitlines() if line.strip()]


def _build_html(notes: list[dict], study_notes: list[str]) -> tuple[str, str]:
    """Returns (subject, html_body)."""
    if notes:
        subject = f"Your reading notes — {len(notes)} saved"
        rendered_items: list[str] = []
        for note in notes:
            title = escape(note.get("book_title") or "Untitled")
            chapter = escape(note.get("chapter") or "")
            main = escape(note.get("passage") or note.get("body") or "")
            detail = ""
            if (
                note.get("kind") == "note"
                and note.get("body")
                and note.get("passage")
            ):
                detail = (
                    "<div style='color:#1A98C9;margin-top:2px'>"
                    f"{escape(note['body'])}</div>"
                )
            rendered_items.append(
                "<li style='margin-bottom:14px'>"
                f"<div style='font-weight:600;color:#1A1A1A'>{title}"
                f"{' · ' + chapter if chapter else ''}</div>"
                f"<div style='color:#444;margin-top:2px'>{main}</div>"
                f"{detail}</li>"
            )
        items = "".join(rendered_items)
        body_inner = f"<ul style='list-style:none;padding:0;margin:0'>{items}</ul>"
        intro = "Here are the highlights and notes you saved while reading."
    else:
        subject = "5 study notes from your current books"
        items = "".join(
            f"<li style='margin-bottom:12px;color:#333'>{escape(s)}</li>"
            for s in study_notes
        )
        body_inner = f"<ul style='padding-left:18px;margin:0'>{items}</ul>"
        intro = (
            "You haven't saved notes yet, so here are study notes generated from the "
            "books you're currently reading."
        )

    html = f"""\
<div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:560px;margin:0 auto;padding:24px">
  <div style="font-size:22px;font-weight:700;color:#1A1A1A">ReadSync</div>
  <div style="color:#666;margin:6px 0 18px">{intro}</div>
  {body_inner}
  <div style="color:#999;font-size:12px;margin-top:24px">
    You're receiving this because daily notes email is on in ReadSync.
  </div>
</div>"""
    return subject, html


def _send_email(to_email: str, subject: str, html: str) -> bool:
    if not settings.resend_api_key:
        log.error("RESEND_API_KEY is not set; cannot send email")
        return False
    try:
        resp = httpx.post(
            "https://api.resend.com/emails",
            headers={"Authorization": f"Bearer {settings.resend_api_key}"},
            json={
                "from": settings.digest_from_email,
                "to": [to_email],
                "subject": subject,
                "html": html,
            },
            timeout=30,
        )
        if resp.status_code >= 400:
            # Resend returns a JSON error body explaining exactly why.
            log.error(
                "Resend rejected email to %s (status %s). from=%r body=%s",
                to_email,
                resp.status_code,
                settings.digest_from_email,
                resp.text,
            )
            resp.raise_for_status()
        log.info("Resend accepted email to %s: %s", to_email, resp.text)
        return True
    except Exception as exc:  # noqa: BLE001
        log.error("Sending email to %s failed: %s", to_email, exc)
        return False


def run_for_subscriber(subscriber: dict, force: bool = False) -> dict:
    """Build and send the digest for one subscriber. Returns a status dict."""
    owner_id = subscriber["owner_id"]
    email = subscriber.get("email")
    if not email:
        return {"owner_id": owner_id, "sent": False, "reason": "no_email"}
    if not force and _already_sent_today(subscriber):
        return {"owner_id": owner_id, "sent": False, "reason": "already_sent_today"}

    notes = fetch_notes(owner_id)
    study_notes: list[str] = []
    if not notes:
        study_notes = _generate_study_notes(fetch_active_books(owner_id))
        if not study_notes:
            return {"owner_id": owner_id, "sent": False, "reason": "nothing_to_send"}

    subject, html = _build_html(notes, study_notes)
    log.info(
        "Sending digest to %s (owner=%s, notes=%d, study_notes=%d)",
        email,
        owner_id,
        len(notes),
        len(study_notes),
    )
    sent = _send_email(email, subject, html)
    if sent:
        mark_sent(owner_id)
    return {"owner_id": owner_id, "sent": sent, "reason": "ok" if sent else "email_failed"}
