from datetime import datetime, timedelta, timezone

import jwt
import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app.api.auth import get_current_user


SECRET = "test-signing-secret-that-is-at-least-32-bytes"


def credentials(token: str) -> HTTPAuthorizationCredentials:
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


def test_authentication_is_required():
    with pytest.raises(HTTPException) as error:
        get_current_user(None)

    assert error.value.status_code == 401


def test_missing_signing_secret_fails_closed(monkeypatch):
    monkeypatch.delenv("SUPABASE_JWT_SECRET", raising=False)
    token = jwt.encode(
        {
            "sub": "00000000-0000-0000-0000-000000000001",
            "aud": "authenticated",
            "exp": datetime.now(timezone.utc) + timedelta(minutes=5),
        },
        SECRET,
        algorithm="HS256",
    )

    with pytest.raises(HTTPException) as error:
        get_current_user(credentials(token))

    assert error.value.status_code == 503


def test_valid_supabase_token_returns_authenticated_identity(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    token = jwt.encode(
        {
            "sub": "00000000-0000-0000-0000-000000000001",
            "email": "person@example.com",
            "aud": "authenticated",
            "exp": datetime.now(timezone.utc) + timedelta(minutes=5),
        },
        SECRET,
        algorithm="HS256",
    )

    user = get_current_user(credentials(token))

    assert user.id == "00000000-0000-0000-0000-000000000001"
    assert user.email == "person@example.com"


def test_expired_token_is_rejected(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    token = jwt.encode(
        {
            "sub": "00000000-0000-0000-0000-000000000001",
            "aud": "authenticated",
            "exp": datetime.now(timezone.utc) - timedelta(minutes=1),
        },
        SECRET,
        algorithm="HS256",
    )

    with pytest.raises(HTTPException) as error:
        get_current_user(credentials(token))

    assert error.value.status_code == 401
