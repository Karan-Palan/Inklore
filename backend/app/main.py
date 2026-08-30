"""ReadSync backend entrypoint.

Exposes a health check and the daily-digest route. The digest can be triggered
immediately for the signed-in user (POST /api/v1/daily-digest) or run for every
subscriber by the scheduled cron job in app/jobs/daily_digest_job.py.
"""
from fastapi import FastAPI

from app.routes import ai, daily_digest

app = FastAPI(title="ReadSync Backend")

app.include_router(daily_digest.router)
app.include_router(ai.router)


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}

# 10x preview-agent hook: internal route used only by the 10x
# control plane.
import os as _tenx_preview_os

try:
    from .tenx_preview_agent import router as tenx_preview_agent_router
except ImportError:
    from app.tenx_preview_agent import router as tenx_preview_agent_router

if _tenx_preview_os.getenv("TENX_PREVIEW_AGENT_TOKEN"):
    app.include_router(tenx_preview_agent_router)

# NOTE: the internal jobs runner (/api/_tenx/jobs/run) is auto-managed and
# mounted by the 10x control plane at deploy time. It must not be defined in
# app source or declared in tenx.yaml.

# 10x jobs hook: internal route used by the 10x control plane for
# short scheduled jobs on the warm Paid Backend runtime.
try:
    from .tenx_jobs import router as tenx_jobs_router
except ImportError:
    from app.tenx_jobs import router as tenx_jobs_router

app.include_router(tenx_jobs_router)


# 10x observability hook: ships one record per served request back
# to 10x so the app can chart real API traffic. Fail-silent — it
# never affects user requests.
try:
    from .tenx_observability import install as _tenx_observability_install
except ImportError:
    from app.tenx_observability import install as _tenx_observability_install

_tenx_observability_install(app)
