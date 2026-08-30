import base64
import os
import threading
from pathlib import Path

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel


router = APIRouter(prefix=os.getenv("TENX_PREVIEW_AGENT_PATH_PREFIX", "/__tenx/preview-agent"))


class PreviewFileDelta(BaseModel):
    path: str
    content: str | None = None
    encoding: str = "utf8"
    deleted: bool = False
    sha256: str | None = None


class PreviewSyncRequest(BaseModel):
    files: list[PreviewFileDelta] = []
    restart: bool = True
    reason: str | None = None
    tenxConfig: dict = {}
    sourceManifest: dict = {}


class PreviewRestartRequest(BaseModel):
    reason: str | None = None


def _workspace_root() -> Path:
    configured = os.getenv("TENX_WORKSPACE_ROOT", "/workspace")
    return Path(configured).resolve()


def _authorize(authorization: str | None) -> None:
    expected = os.getenv("TENX_PREVIEW_AGENT_TOKEN", "")
    if not expected:
        raise HTTPException(status_code=404, detail="Preview agent is disabled.")
    prefix = "Bearer "
    token = authorization[len(prefix):] if authorization and authorization.startswith(prefix) else ""
    if token != expected:
        raise HTTPException(status_code=401, detail="Unauthorized preview agent request.")


def _safe_path(relative_path: str) -> Path:
    clean = relative_path.strip().lstrip("/")
    if not clean or ".." in Path(clean).parts:
        raise HTTPException(status_code=422, detail=f"Invalid path: {relative_path}")
    if not (clean == "tenx.yaml" or clean.startswith("backend/") or clean.startswith("services/")):
        raise HTTPException(status_code=422, detail=f"Path is outside sync roots: {relative_path}")
    root = _workspace_root()
    target = (root / clean).resolve()
    if root not in target.parents and target != root:
        raise HTTPException(status_code=422, detail=f"Path escapes workspace: {relative_path}")
    return target


def _schedule_restart() -> None:
    def exit_process() -> None:
        os._exit(3)

    threading.Timer(0.25, exit_process).start()


@router.post("/sync")
async def sync_preview(payload: PreviewSyncRequest, authorization: str | None = Header(default=None)):
    _authorize(authorization)
    changed: list[str] = []
    for file_delta in payload.files:
        target = _safe_path(file_delta.path)
        if file_delta.deleted:
            if target.exists():
                target.unlink()
            changed.append(file_delta.path)
            continue
        if file_delta.content is None:
            raise HTTPException(status_code=422, detail=f"Missing content for {file_delta.path}")
        target.parent.mkdir(parents=True, exist_ok=True)
        if file_delta.encoding == "base64":
            target.write_bytes(base64.b64decode(file_delta.content))
        elif file_delta.encoding == "utf8":
            target.write_text(file_delta.content, encoding="utf-8")
        else:
            raise HTTPException(status_code=422, detail=f"Unsupported encoding for {file_delta.path}")
        changed.append(file_delta.path)
    if payload.restart:
        _schedule_restart()
    return {"status": "accepted", "changed": changed, "restart": payload.restart}


@router.post("/restart")
async def restart_preview(payload: PreviewRestartRequest, authorization: str | None = Header(default=None)):
    _authorize(authorization)
    _schedule_restart()
    return {"status": "accepted", "restart": True}
