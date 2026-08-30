"""Scheduled cron entrypoint: send the daily digest to every enabled subscriber.

Registered as `daily_digest_cron` in tenx.yaml and run by the 10x Paid Backend
scheduler. Runs once per day; per-subscriber `last_sent_at` prevents duplicate
sends if the job is retried.
"""
import logging

from app import digest

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("daily_digest_cron")


def main() -> None:
    subscribers = digest.fetch_enabled_subscribers()
    log.info("daily_digest_cron: %d enabled subscriber(s)", len(subscribers))
    if not subscribers:
        log.warning(
            "daily_digest_cron: no enabled subscribers — nothing to send. "
            "A user must enable daily notes email in the app first."
        )
    sent = 0
    for subscriber in subscribers:
        result = digest.run_for_subscriber(subscriber, force=False)
        log.info(
            "daily_digest_cron: owner=%s sent=%s reason=%s",
            result.get("owner_id"),
            result.get("sent"),
            result.get("reason"),
        )
        if result.get("sent"):
            sent += 1
    log.info(
        "daily_digest_cron: processed %d subscribers, sent %d", len(subscribers), sent
    )


if __name__ == "__main__":
    main()
