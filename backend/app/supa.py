"""Thin PostgREST client using the service-role key (bypasses RLS).

Kept deliberately transparent — every call maps 1:1 to a Supabase REST
request, so there's no client-library magic between us and the database.
"""

from typing import Any

import httpx

from .config import settings


def _headers(*, returning: bool = False) -> dict[str, str]:
    key = settings().supabase_service_role_key
    headers = {
        "apikey": key,
        "authorization": f"Bearer {key}",
        "content-type": "application/json",
    }
    if returning:
        headers["prefer"] = "return=representation"
    return headers


def _rest(path: str) -> str:
    return f"{settings().supabase_url}/rest/v1/{path}"


async def insert(table: str, row: dict[str, Any]) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.post(
            _rest(table), json=row, headers=_headers(returning=True)
        )
        resp.raise_for_status()
        return resp.json()[0]


async def select(
    table: str, *, filters: dict[str, str], columns: str = "*"
) -> list[dict[str, Any]]:
    """filters use PostgREST operators, e.g. {"id": "eq.<uuid>"}."""
    params = {"select": columns, **filters}
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(_rest(table), params=params, headers=_headers())
        resp.raise_for_status()
        return resp.json()


async def update(
    table: str, *, filters: dict[str, str], patch: dict[str, Any]
) -> list[dict[str, Any]]:
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.patch(
            _rest(table),
            params=filters,
            json=patch,
            headers=_headers(returning=True),
        )
        resp.raise_for_status()
        return resp.json()


async def upsert(
    table: str, row: dict[str, Any], *, on_conflict: str
) -> dict[str, Any]:
    headers = _headers(returning=True)
    headers["prefer"] = "return=representation,resolution=merge-duplicates"
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.post(
            _rest(table),
            params={"on_conflict": on_conflict},
            json=row,
            headers=headers,
        )
        resp.raise_for_status()
        return resp.json()[0]


async def rpc(fn: str, args: dict[str, Any]) -> Any:
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.post(_rest(f"rpc/{fn}"), json=args, headers=_headers())
        resp.raise_for_status()
        return resp.json()
