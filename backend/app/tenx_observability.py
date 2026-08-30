"""10x observability — platform-managed; do not edit.

Records one entry per served HTTP request and ships batches to 10x so the
app can chart real API traffic. Fail-silent by design: telemetry never
affects user requests.
"""
import asyncio
import os
import time
from datetime import datetime, timezone

import httpx

_FLUSH_INTERVAL_SECONDS = 5.0
_MAX_BATCH = 200
_MAX_QUEUE = 2000
# Reported with every batch so the platform can see which recorder
# versions the fleet runs before changing the ingest contract.
_CLIENT = "tenx-obs/1"

_queue = []


def _config():
    # Preview machines never ship telemetry — the API tab charts
    # production traffic only.
    if os.getenv("TENX_PREVIEW_MODE", "").strip():
        return None
    host = os.getenv("TENX_API_HOST", "").strip()
    backend_id = os.getenv("TENX_BACKEND_ID", "").strip()
    token = os.getenv("TENX_INGEST_TOKEN", "").strip()
    if not host or not backend_id or not token:
        return None
    return {
        "url": f"https://{host}/api/v1/backends/{backend_id}/runtime-logs/ingest",
        "token": token,
        "environment_id": os.getenv("TENX_ENVIRONMENT_ID", "").strip(),
        "deployment_number": os.getenv("TENX_DEPLOYMENT_NUMBER", "").strip(),
    }


def _skip(path):
    preview_prefix = os.getenv("TENX_PREVIEW_AGENT_PATH_PREFIX", "/__tenx/preview-agent")
    return (
        path == "/healthz"
        or path.startswith("/__tenx/")
        or path.startswith("/_tenx/")
        or path.startswith(preview_prefix)
    )


async def _flush(client, config):
    global _queue
    if not _queue:
        return
    batch, _queue = _queue[:_MAX_BATCH], _queue[_MAX_BATCH:]
    try:
        await client.post(
            config["url"],
            json={
                "client": _CLIENT,
                "environmentId": config["environment_id"] or None,
                "requests": batch,
            },
            headers={"Authorization": f"Bearer {config['token']}"},
            timeout=10.0,
        )
    except Exception:
        # Dropped telemetry beats a retry storm.
        pass


async def _flush_loop(config):
    async with httpx.AsyncClient() as client:
        while True:
            try:
                await asyncio.sleep(_FLUSH_INTERVAL_SECONDS)
                await _flush(client, config)
            except asyncio.CancelledError:
                await _flush(client, config)
                raise
            except Exception:
                pass


def install(app):
    """Attach the request recorder and its background shipper."""
    config = _config()
    if config is None:
        return

    @app.middleware("http")
    async def _tenx_record_requests(request, call_next):
        path = request.url.path or "/"
        if _skip(path):
            return await call_next(request)
        started = time.monotonic()
        status_code = 500
        try:
            response = await call_next(request)
            status_code = response.status_code
            return response
        finally:
            try:
                if len(_queue) < _MAX_QUEUE:
                    record = {
                        "method": request.method,
                        "path": path,
                        "status": status_code,
                        "durationMs": int((time.monotonic() - started) * 1000),
                        "requestedAt": datetime.now(timezone.utc).isoformat(),
                    }
                    if config["deployment_number"]:
                        record["deploymentNumber"] = config["deployment_number"]
                    _queue.append(record)
            except Exception:
                pass

    @app.on_event("startup")
    async def _tenx_start_observability():
        try:
            asyncio.create_task(_flush_loop(config))
        except Exception:
            pass
