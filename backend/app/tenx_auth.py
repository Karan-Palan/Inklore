"""Resolve the verified current user for authenticated backend routes.

The FastAPI app is directly reachable through its Vercel URL, where the 10x
gateway is not guaranteed to be in front of every request. An unverified JWT
``sub`` would let a caller impersonate any account, so these routes fail closed
until a signing-key endpoint is configured.
"""
import os

from fastapi import HTTPException, Request
from jwt import PyJWKClient, decode as jwt_decode

_jwk_client: PyJWKClient | None = None
_jwk_client_url: str | None = None


def _jwks_url() -> str:
    return os.environ.get("TENX_AUTH_JWKS_URL", "").strip()


def _client() -> PyJWKClient | None:
    global _jwk_client, _jwk_client_url
    jwks_url = _jwks_url()
    if not jwks_url:
        return None
    if _jwk_client is None or _jwk_client_url != jwks_url:
        _jwk_client = PyJWKClient(jwks_url)
        _jwk_client_url = jwks_url
    return _jwk_client


def _subject_from_token(token: str) -> str | None:
    """Return a subject only after successful JWT signature verification."""
    try:
        client = _client()
        if client is None:
            return None
        signing_key = client.get_signing_key_from_jwt(token)
        claims = jwt_decode(
            token,
            signing_key.key,
            algorithms=["RS256", "ES256"],
            options={"verify_aud": False},
        )
        subject = claims.get("sub")
        return subject if isinstance(subject, str) and subject else None
    except Exception:  # noqa: BLE001 - invalid tokens are never identities
        return None


def current_user(request: Request) -> dict:
    if _client() is None:
        raise HTTPException(status_code=503, detail="token verification is not configured")
    header = request.headers.get("Authorization", "")
    if not header.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    token = header.split(" ", 1)[1].strip()
    sub = _subject_from_token(token)
    if not sub:
        raise HTTPException(status_code=401, detail="token missing subject")
    return {"sub": sub}
