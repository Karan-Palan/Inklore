"""Daily and weekly reading recaps, built from local app syncs.

The app writes a compact mirror of current books, saved notes, and reading
minutes. Cron selects recipients by their IANA timezone, so a reader gets a
daily recap at about 08:00 and a weekly recap on Monday morning without an
account being required during the hackathon build.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from hashlib import sha256
from html import escape
import logging
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import httpx

from app import db
from app.config import settings
from app.providers.openai import OpenAIProviderError, generate_text

log = logging.getLogger("inkflow_digest")


def _safe_zone(timezone_name: str | None) -> str:
    try:
        ZoneInfo(timezone_name or "")
        return timezone_name or "UTC"
    except ZoneInfoNotFoundError:
        return "UTC"


def fetch_subscriber(owner_id: str) -> dict | None:
    rows = db.query(
        """
        SELECT owner_id, email, enabled, daily_enabled, weekly_enabled, timezone,
               last_sent_at, last_daily_sent_at, last_weekly_sent_at
        FROM digest_subscribers WHERE owner_id = %s
        """,
        (owner_id,),
    )
    return rows[0] if rows else None


def fetch_enabled_subscribers() -> list[dict]:
    return db.query(
        """
        SELECT owner_id, email, enabled, daily_enabled, weekly_enabled, timezone,
               last_sent_at, last_daily_sent_at, last_weekly_sent_at
        FROM digest_subscribers WHERE daily_enabled = true OR weekly_enabled = true
        """
    )


def upsert_subscriber(
    owner_id: str,
    email: str,
    daily_enabled: bool,
    weekly_enabled: bool,
    timezone_name: str,
) -> dict:
    clean_email = email.strip().lower()
    zone = _safe_zone(timezone_name)
    db.execute(
        """
        INSERT INTO digest_subscribers
          (owner_id, email, enabled, daily_enabled, weekly_enabled, timezone, updated_at)
        VALUES (%s, %s, %s, %s, %s, %s, now())
        ON CONFLICT (owner_id) DO UPDATE SET
          email=EXCLUDED.email, enabled=EXCLUDED.enabled,
          daily_enabled=EXCLUDED.daily_enabled, weekly_enabled=EXCLUDED.weekly_enabled,
          timezone=EXCLUDED.timezone, updated_at=now()
        """,
        (owner_id, clean_email, daily_enabled, daily_enabled, weekly_enabled, zone),
    )
    return fetch_subscriber(owner_id) or {}


def replace_notes(owner_id: str, notes: list[dict]) -> None:
    with db.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM digest_notes WHERE owner_id = %s", (owner_id,))
            for note in notes[:200]:
                cur.execute(
                    """
                    INSERT INTO digest_notes
                      (id, owner_id, kind, book_title, chapter, passage, body, created_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        note.get("id"), owner_id, note.get("kind", "note"),
                        note.get("book_title", ""), note.get("chapter", ""),
                        note.get("passage", ""), note.get("body", ""),
                        note.get("created_at") or datetime.now(timezone.utc).isoformat(),
                    ),
                )
        conn.commit()


def replace_books(owner_id: str, books: list[dict]) -> None:
    with db.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM digest_books WHERE owner_id = %s", (owner_id,))
            for book in books[:20]:
                cur.execute(
                    """
                    INSERT INTO digest_books
                      (id, owner_id, title, author, excerpt, is_active, progress,
                       current_chapter, last_read_at, updated_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, now())
                    """,
                    (
                        book.get("id"), owner_id, book.get("title", ""),
                        book.get("author", ""), (book.get("excerpt") or "")[:4000],
                        bool(book.get("is_active", True)),
                        min(1, max(0, float(book.get("progress", 0) or 0))),
                        book.get("current_chapter", ""), book.get("last_read_at"),
                    ),
                )
        conn.commit()


def replace_activity(owner_id: str, activity: list[dict]) -> None:
    with db.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM digest_activity WHERE owner_id = %s", (owner_id,))
            for row in activity[:90]:
                try:
                    activity_date = date.fromisoformat(str(row.get("date")))
                except ValueError:
                    continue
                cur.execute(
                    """
                    INSERT INTO digest_activity
                      (owner_id, activity_date, read_minutes, listen_minutes, pages_read, updated_at)
                    VALUES (%s, %s, %s, %s, %s, now())
                    ON CONFLICT (owner_id, activity_date) DO UPDATE SET
                      read_minutes=EXCLUDED.read_minutes,
                      listen_minutes=EXCLUDED.listen_minutes,
                      pages_read=EXCLUDED.pages_read,
                      updated_at=now()
                    """,
                    (
                        owner_id, activity_date,
                        max(0, int(row.get("read_minutes", 0) or 0)),
                        max(0, int(row.get("listen_minutes", 0) or 0)),
                        max(0, int(row.get("pages_read", 0) or 0)),
                    ),
                )
        conn.commit()


def _period_bounds(kind: str, zone: ZoneInfo, now: datetime) -> tuple[datetime, datetime, str]:
    local_now = now.astimezone(zone)
    if kind == "daily":
        end_day = local_now.date()
        start_day = end_day - timedelta(days=1)
        start = datetime.combine(start_day, datetime.min.time(), tzinfo=zone)
        end = datetime.combine(end_day, datetime.min.time(), tzinfo=zone)
        return start, end, start_day.isoformat()
    end_day = local_now.date() - timedelta(days=local_now.weekday())
    start_day = end_day - timedelta(days=7)
    start = datetime.combine(start_day, datetime.min.time(), tzinfo=zone)
    end = datetime.combine(end_day, datetime.min.time(), tzinfo=zone)
    return start, end, f"{start_day.isoformat()}:{(end_day - timedelta(days=1)).isoformat()}"


def _activity(owner_id: str, start: datetime, end: datetime) -> dict:
    rows = db.query(
        """
        SELECT coalesce(sum(read_minutes), 0) AS read_minutes,
               coalesce(sum(listen_minutes), 0) AS listen_minutes,
               coalesce(sum(pages_read), 0) AS pages_read,
               count(*) FILTER (WHERE read_minutes + listen_minutes > 0) AS active_days
        FROM digest_activity
        WHERE owner_id=%s AND activity_date >= %s AND activity_date < %s
        """,
        (owner_id, start.date(), end.date()),
    )
    return rows[0] if rows else {
        "read_minutes": 0, "listen_minutes": 0, "pages_read": 0, "active_days": 0,
    }


def _notes(owner_id: str, start: datetime, end: datetime) -> list[dict]:
    return db.query(
        """
        SELECT kind, book_title, chapter, passage, body, created_at
        FROM digest_notes
        WHERE owner_id=%s AND created_at >= %s AND created_at < %s
        ORDER BY created_at DESC LIMIT 30
        """,
        (owner_id, start.astimezone(timezone.utc), end.astimezone(timezone.utc)),
    )


def _books(owner_id: str, start: datetime) -> list[dict]:
    return db.query(
        """
        SELECT title, author, excerpt, progress, current_chapter, last_read_at
        FROM digest_books
        WHERE owner_id=%s AND is_active=true
          AND (last_read_at IS NULL OR last_read_at >= %s)
        ORDER BY last_read_at DESC NULLS LAST LIMIT 8
        """,
        (owner_id, start.astimezone(timezone.utc)),
    )


def _important_points(notes: list[dict], books: list[dict], kind: str) -> list[str]:
    source_parts = []
    for note in notes[:12]:
        source_parts.append(f"{note.get('book_title')}: {note.get('passage') or note.get('body')}")
    for book in books[:4]:
        if book.get("excerpt"):
            source_parts.append(f"{book.get('title')}: {book.get('excerpt')[:1000]}")
    if not source_parts or not settings.openai_api_key:
        return []
    try:
        response = generate_text(
            instructions=(
                f"You are Inkflow's thoughtful {kind} reading recap editor. "
                "Use only the source material. Write 3 terse, specific takeaways, "
                "one per line, without a heading, markdown, or invented details."
            ),
            input_text="\n\n".join(source_parts)[:12_000],
            max_output_tokens=450,
        )
    except OpenAIProviderError as exc:
        log.warning("Could not generate recap takeaways: %s", exc)
        return []
    return [line.strip(" -•\t") for line in response.splitlines() if line.strip()][:3]


def _html(kind: str, period_label: str, activity: dict, notes: list[dict], books: list[dict], points: list[str]) -> tuple[str, str]:
    read = int(activity.get("read_minutes", 0) or 0)
    listened = int(activity.get("listen_minutes", 0) or 0)
    pages = int(activity.get("pages_read", 0) or 0)
    active_days = int(activity.get("active_days", 0) or 0)
    total = read + listened
    heading = "Yesterday, in Inkflow" if kind == "daily" else "Your week in Inkflow"
    subject = f"Your reading recap: {total} minutes yesterday" if kind == "daily" else f"Your weekly reading recap: {total} minutes"
    stats = f"{total} min total · {read} read · {listened} listened · {pages} pages"
    if kind == "weekly":
        stats += f" · {active_days} active days"
    rendered_books = "".join(
        "<li style='margin:8px 0'><strong>"
        f"{escape(book.get('title') or 'Untitled')}</strong>"
        f"{(' · ' + escape(book.get('current_chapter'))) if book.get('current_chapter') else ''}"
        f" <span style='color:#68736e'>({int(float(book.get('progress') or 0) * 100)}%)</span></li>"
        for book in books
    ) or "<li>No new book progress was synced for this period.</li>"
    rendered_points = "".join(f"<li style='margin:8px 0'>{escape(point)}</li>" for point in points)
    if not rendered_points and notes:
        rendered_points = "".join(
            f"<li style='margin:8px 0'>{escape(note.get('passage') or note.get('body') or '')}</li>"
            for note in notes[:3]
        )
    if not rendered_points:
        rendered_points = "<li>Open a chapter today and Inkflow will have a recap waiting tomorrow.</li>"
    html = f"""\
<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;max-width:580px;margin:0 auto;padding:28px;color:#203d38">
  <div style="font-size:13px;font-weight:700;letter-spacing:1.2px;color:#cb6f38">INKFLOW</div>
  <h1 style="font-size:28px;margin:10px 0 4px">{heading}</h1>
  <p style="margin:0 0 22px;color:#68736e">{escape(period_label)}</p>
  <div style="background:#eef2ed;border-radius:14px;padding:16px;font-size:16px;font-weight:600">{escape(stats)}</div>
  <h2 style="font-size:18px;margin:28px 0 8px">Books you moved through</h2>
  <ul style="padding-left:20px;margin:0">{rendered_books}</ul>
  <h2 style="font-size:18px;margin:28px 0 8px">Ideas worth keeping</h2>
  <ul style="padding-left:20px;margin:0">{rendered_points}</ul>
  <p style="margin-top:30px;color:#8a938f;font-size:12px">You’re receiving this because reading recap email is on in Inkflow.</p>
</div>"""
    return subject, html


def _send_email(to_email: str, subject: str, html: str, idempotency_key: str) -> bool:
    if not settings.resend_api_key:
        log.warning("RESEND_API_KEY is not configured; digest was not sent")
        return False
    try:
        response = httpx.post(
            "https://api.resend.com/emails",
            headers={"Authorization": f"Bearer {settings.resend_api_key}", "Idempotency-Key": idempotency_key},
            json={"from": settings.digest_from_email, "to": [to_email], "subject": subject, "html": html},
            timeout=30,
        )
        if response.status_code >= 400:
            log.warning("Recap email rejected (%s): %s", response.status_code, response.text[:500])
            return False
        return True
    except httpx.HTTPError as exc:
        log.warning("Recap email request failed: %s", exc)
        return False


def _last_sent_key(kind: str) -> str:
    return "last_daily_sent_at" if kind == "daily" else "last_weekly_sent_at"


def _mark_sent(owner_id: str, kind: str) -> None:
    column = _last_sent_key(kind)
    db.execute(f"UPDATE digest_subscribers SET {column}=now(), last_sent_at=now() WHERE owner_id=%s", (owner_id,))


def _already_sent(subscriber: dict, kind: str, now: datetime) -> bool:
    last = subscriber.get(_last_sent_key(kind))
    if not last:
        return False
    if isinstance(last, str):
        try:
            last = datetime.fromisoformat(last)
        except ValueError:
            return False
    zone = ZoneInfo(_safe_zone(subscriber.get("timezone")))
    start, _, _ = _period_bounds(kind, zone, now)
    return last.astimezone(zone) >= start


def run_for_subscriber(subscriber: dict, kind: str, *, force: bool = False, now: datetime | None = None) -> dict:
    if kind not in {"daily", "weekly"}:
        raise ValueError("kind must be daily or weekly")
    now = now or datetime.now(timezone.utc)
    owner_id = subscriber["owner_id"]
    email = subscriber.get("email")
    enabled = bool(subscriber.get(f"{kind}_enabled"))
    if not email:
        return {"owner_id": owner_id, "sent": False, "reason": "no_email"}
    if not enabled and not force:
        return {"owner_id": owner_id, "sent": False, "reason": "disabled"}
    if not force and _already_sent(subscriber, kind, now):
        return {"owner_id": owner_id, "sent": False, "reason": "already_sent"}
    zone = ZoneInfo(_safe_zone(subscriber.get("timezone")))
    start, end, period_key = _period_bounds(kind, zone, now)
    activity = _activity(owner_id, start, end)
    notes = _notes(owner_id, start, end)
    books = _books(owner_id, start)
    points = _important_points(notes, books, kind)
    subject, html = _html(kind, period_key, activity, notes, books, points)
    hash_owner = sha256(owner_id.encode()).hexdigest()[:20]
    sent = _send_email(email, subject, html, f"inkflow-{kind}-{hash_owner}-{period_key}")
    if sent:
        _mark_sent(owner_id, kind)
    return {"owner_id": owner_id, "sent": sent, "reason": "ok" if sent else "email_failed"}


def run_due(now: datetime | None = None) -> dict[str, int]:
    now = now or datetime.now(timezone.utc)
    result = {"daily": 0, "weekly": 0}
    for subscriber in fetch_enabled_subscribers():
        zone = ZoneInfo(_safe_zone(subscriber.get("timezone")))
        local_now = now.astimezone(zone)
        if local_now.hour != 8:
            continue
        if subscriber.get("daily_enabled") and run_for_subscriber(subscriber, "daily", now=now)["sent"]:
            result["daily"] += 1
        if local_now.weekday() == 0 and subscriber.get("weekly_enabled") and run_for_subscriber(subscriber, "weekly", now=now)["sent"]:
            result["weekly"] += 1
    return result
