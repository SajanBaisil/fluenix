"""Gemini Live ephemeral tokens.

The app never sees the real API key: /v1/session mints a single-use,
short-lived token constrained to our Live model, and the client opens the
WebSocket with `?access_token=<token>` instead of `?key=...`.

Docs: https://ai.google.dev/gemini-api/docs/ephemeral-tokens
"""

from datetime import UTC, datetime, timedelta
from typing import Any

import httpx

from .config import settings

_BASE = "https://generativelanguage.googleapis.com"


class TokenMintError(Exception):
    pass


async def mint_live_token() -> dict[str, Any]:
    """Returns {"token": str, "expire_time": iso8601}."""
    now = datetime.now(UTC)
    body = {
        "uses": 1,
        # The websocket must be *opened* within this window...
        "newSessionExpireTime": (now + timedelta(minutes=2)).isoformat(),
        # ...and the call itself can run until this hard stop.
        "expireTime": (now + timedelta(minutes=35)).isoformat(),
        # NOTE: no bidiGenerateContentSetup lock — a locked setup makes the
        # Constrained websocket close 1011 when the client sends its own
        # setup (verified 2026-07-23). Single-use + short expiry is the
        # security boundary; the client connects to
        # .../v1alpha.GenerativeService.BidiGenerateContentConstrained with
        # header `Authorization: Token <name>`.
    }
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.post(
            f"{_BASE}/v1alpha/auth_tokens",
            params={"key": settings().gemini_api_key},
            json=body,
        )
    if resp.status_code != 200:
        raise TokenMintError(f"{resp.status_code}: {resp.text[:300]}")
    data = resp.json()
    token = data.get("name")
    if not token:
        raise TokenMintError(f"no token in response: {data}")
    return {"token": token, "expire_time": body["expireTime"]}
