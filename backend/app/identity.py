"""Request identity for the no-sign-in hackathon build.

Each app installation sends a random UUID in ``X-Inkflow-Installation-ID``.
It is deliberately namespaced before storage so it cannot collide with a future
authenticated user subject.  The server never accepts an arbitrary owner id.
"""
from __future__ import annotations

from uuid import UUID

from fastapi import Header, HTTPException, status


def installation_owner(
    x_inkflow_installation_id: str | None = Header(default=None),
) -> str:
    if not x_inkflow_installation_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Inkflow installation identity",
        )
    try:
        installation_id = UUID(x_inkflow_installation_id.strip())
    except (ValueError, AttributeError) as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid Inkflow installation identity",
        ) from exc
    return f"anon:{installation_id}"
