from __future__ import annotations

import os
import uuid
from dataclasses import dataclass
from functools import lru_cache

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer


security = HTTPBearer(auto_error=False)
SUPPORTED_ALGORITHMS = {"HS256", "RS256", "ES256"}


@dataclass(frozen=True)
class AuthenticatedUser:
    id: str
    email: str | None = None


@lru_cache(maxsize=4)
def _jwks_client(supabase_url: str) -> jwt.PyJWKClient:
    return jwt.PyJWKClient(
        f"{supabase_url}/auth/v1/.well-known/jwks.json",
        cache_keys=True,
    )


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> AuthenticatedUser:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
        )

    try:
        token = credentials.credentials
        algorithm = jwt.get_unverified_header(token).get("alg")
        if algorithm not in SUPPORTED_ALGORITHMS:
            raise jwt.InvalidAlgorithmError("Unsupported signing algorithm")

        supabase_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
        decode_options = {
            "algorithms": [algorithm],
            "audience": "authenticated",
            "options": {"require": ["exp", "sub"]},
        }
        if supabase_url:
            decode_options["issuer"] = f"{supabase_url}/auth/v1"

        if algorithm == "HS256":
            signing_key = os.environ.get("SUPABASE_JWT_SECRET")
            if not signing_key:
                raise RuntimeError("Missing Supabase JWT secret")
        else:
            if not supabase_url:
                raise RuntimeError("Missing Supabase URL")
            signing_key = _jwks_client(supabase_url).get_signing_key_from_jwt(token).key

        payload = jwt.decode(token, signing_key, **decode_options)
        uuid.UUID(payload["sub"])
    except RuntimeError as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service is not configured",
        ) from error
    except (jwt.PyJWTError, ValueError, TypeError) as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token",
        ) from error

    return AuthenticatedUser(id=payload["sub"], email=payload.get("email"))
