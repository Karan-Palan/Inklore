import asyncio
import importlib
import inspect
import os
from dataclasses import dataclass
from typing import Any

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel


router = APIRouter(prefix="/_tenx/jobs")


class JobRunRequest(BaseModel):
    job_key: str
    run_id: str
    trigger: str = "manual"
    handler: str
    timeout_seconds: int = 300
    project_id: str | None = None
    backend_id: str | None = None
    environment_id: str | None = None
    api_host: str | None = None


@dataclass(frozen=True)
class TenXJobContext:
    job_key: str
    run_id: str
    trigger: str
    timeout_seconds: int
    project_id: str | None = None
    backend_id: str | None = None
    environment_id: str | None = None
    api_host: str | None = None


def _authorize(router_token: str | None) -> None:
    expected = os.getenv("TENX_ROUTER_SHARED_SECRET", "")
    if not expected:
        raise HTTPException(status_code=404, detail="Job runner is disabled.")
    if router_token != expected:
        raise HTTPException(status_code=404, detail="Not found")


def _load_handler(ref: str):
    module_name, _, attr_name = ref.strip().rpartition(".")
    if not module_name or not attr_name:
        raise HTTPException(status_code=422, detail="Invalid job handler reference.")
    try:
        module = importlib.import_module(module_name)
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Could not import job handler module: {module_name}") from exc
    handler = getattr(module, attr_name, None)
    if handler is None or not callable(handler):
        raise HTTPException(status_code=422, detail=f"Job handler is not callable: {ref}")
    return handler


async def _call_handler(handler, context: TenXJobContext):
    timeout = max(1, min(context.timeout_seconds, 300))
    if inspect.iscoroutinefunction(handler):
        return await asyncio.wait_for(handler(context), timeout=timeout)
    result = await asyncio.wait_for(asyncio.to_thread(handler, context), timeout=timeout)
    if inspect.isawaitable(result):
        return await asyncio.wait_for(result, timeout=timeout)
    return result


@router.post("/run")
async def run_job(request: JobRunRequest, x_tenx_router_token: str | None = Header(default=None)):
    _authorize(x_tenx_router_token)
    handler = _load_handler(request.handler)
    context = TenXJobContext(
        job_key=request.job_key,
        run_id=request.run_id,
        trigger=request.trigger,
        timeout_seconds=request.timeout_seconds,
        project_id=request.project_id,
        backend_id=request.backend_id,
        environment_id=request.environment_id,
        api_host=request.api_host,
    )
    try:
        result = await _call_handler(handler, context)
    except asyncio.TimeoutError:
        return {"status": "failed", "message": "Job handler timed out.", "metrics": {}}
    except Exception as exc:
        return {"status": "failed", "message": str(exc), "metrics": {}}
    if isinstance(result, dict):
        return {
            "status": result.get("status") or "succeeded",
            "message": result.get("message"),
            "metrics": result.get("metrics") if isinstance(result.get("metrics"), dict) else {},
        }
    return {"status": "succeeded", "metrics": {}}