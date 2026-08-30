from fastapi import HTTPException
from starlette.requests import Request

from app import tenx_auth


def request_with_token(token: str) -> Request:
    return Request(
        {
            "type": "http",
            "method": "POST",
            "path": "/api/v1/daily-digest",
            "headers": [(b"authorization", f"Bearer {token}".encode())],
        }
    )


def test_current_user_fails_closed_without_jwks(monkeypatch) -> None:
    monkeypatch.delenv("TENX_AUTH_JWKS_URL", raising=False)

    try:
        tenx_auth.current_user(request_with_token("unsigned-token"))
    except HTTPException as error:
        assert error.status_code == 503
        assert error.detail == "token verification is not configured"
    else:  # pragma: no cover - explicit guard against an auth regression
        raise AssertionError("an unsigned token must never be accepted")


def test_subject_requires_a_verified_token(monkeypatch) -> None:
    class SigningKey:
        key = "test-key"

    class Client:
        def get_signing_key_from_jwt(self, token: str) -> SigningKey:
            assert token == "signed-token"
            return SigningKey()

    monkeypatch.setattr(tenx_auth, "_client", lambda: Client())
    monkeypatch.setattr(
        tenx_auth,
        "jwt_decode",
        lambda token, key, **kwargs: {"sub": "reader-123"},
    )

    assert tenx_auth._subject_from_token("signed-token") == "reader-123"


def test_invalid_signature_has_no_subject(monkeypatch) -> None:
    class Client:
        def get_signing_key_from_jwt(self, token: str) -> None:
            raise RuntimeError("signature lookup failed")

    monkeypatch.setattr(tenx_auth, "_client", lambda: Client())

    assert tenx_auth._subject_from_token("forged-token") is None
