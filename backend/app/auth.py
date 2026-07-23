"""Supabase JWT verification.

Supports both signing schemes:
- legacy projects: HS256 with the project JWT secret
- current projects: asymmetric keys published at /auth/v1/.well-known/jwks.json
"""

import time
from typing import Annotated, Any

import httpx
import jwt
from fastapi import Depends, HTTPException, Request

from .config import settings

_jwks_cache: dict[str, Any] = {"keys": None, "fetched_at": 0.0}
_JWKS_TTL_S = 3600


async def _jwks() -> jwt.PyJWKSet:
    now = time.monotonic()
    if _jwks_cache["keys"] is None or now - _jwks_cache["fetched_at"] > _JWKS_TTL_S:
        url = f"{settings().supabase_url}/auth/v1/.well-known/jwks.json"
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(url)
            resp.raise_for_status()
        _jwks_cache["keys"] = jwt.PyJWKSet.from_dict(resp.json())
        _jwks_cache["fetched_at"] = now
    return _jwks_cache["keys"]


async def current_user_id(request: Request) -> str:
    """Extract and verify the Supabase access token; return the user id."""
    auth = request.headers.get("authorization", "")
    if not auth.lower().startswith("bearer "):
        raise HTTPException(401, "Missing bearer token")
    token = auth[7:]

    try:
        if settings().supabase_jwt_secret:
            claims = jwt.decode(
                token,
                settings().supabase_jwt_secret,
                algorithms=["HS256"],
                audience="authenticated",
            )
        else:
            header = jwt.get_unverified_header(token)
            key = None
            for jwk in (await _jwks()).keys:
                if jwk.key_id == header.get("kid"):
                    key = jwk.key
                    break
            if key is None:
                raise HTTPException(401, "Unknown signing key")
            claims = jwt.decode(
                token,
                key,
                algorithms=[header.get("alg", "ES256")],
                audience="authenticated",
            )
    except jwt.PyJWTError as e:
        raise HTTPException(401, f"Invalid token: {e}") from e

    sub = claims.get("sub")
    if not sub:
        raise HTTPException(401, "Token has no subject")
    return str(sub)


UserId = Annotated[str, Depends(current_user_id)]
