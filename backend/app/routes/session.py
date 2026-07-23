import logging
from datetime import UTC, date, datetime
from typing import Any, Literal

from fastapi import APIRouter, BackgroundTasks, HTTPException
from pydantic import BaseModel, Field

from .. import analysis, gemini, supa
from ..auth import UserId
from ..config import settings

logger = logging.getLogger(__name__)

# Below this, there isn't enough learner speech to analyze meaningfully.
MIN_ANALYSIS_WORDS = 15

router = APIRouter(prefix="/v1")

MIN_CALL_SECONDS = 30  # don't start a call the user can't finish a hello in


# ─────────────────────────────────────────────────────────────
# POST /v1/session — start a call: meter, record, mint token
# ─────────────────────────────────────────────────────────────
class SessionRequest(BaseModel):
    scenario: str = Field(default="casual", max_length=40)
    persona: str = Field(default="emma", max_length=40)


class SessionResponse(BaseModel):
    call_id: str
    provider: Literal["gemini_live"]
    model: str
    token: str
    token_kind: Literal["ephemeral", "dev_raw_key"]
    expire_time: str | None
    remaining_seconds: int


async def _tier(user_id: str) -> str:
    rows = await supa.select(
        "subscriptions",
        filters={"user_id": f"eq.{user_id}", "status": "eq.active"},
        columns="tier",
    )
    return rows[0]["tier"] if rows else "free"


async def _remaining_seconds(user_id: str) -> int:
    used = await supa.rpc("call_seconds_today", {"p_user": user_id})
    tier = await _tier(user_id)
    allowance = (
        settings().premium_daily_seconds
        if tier == "premium"
        else settings().free_daily_seconds
    )
    return max(0, allowance - int(used))


@router.post("/session", response_model=SessionResponse)
async def create_session(body: SessionRequest, user_id: UserId) -> SessionResponse:
    remaining = await _remaining_seconds(user_id)
    if remaining < MIN_CALL_SECONDS:
        raise HTTPException(
            429, {"code": "out_of_minutes", "message": "Daily limit reached."}
        )

    call = await supa.insert(
        "calls",
        {
            "user_id": user_id,
            "scenario": body.scenario,
            "persona": body.persona,
            "provider": "gemini_live",
        },
    )

    try:
        minted = await gemini.mint_live_token()
        token, kind, expire = minted["token"], "ephemeral", minted["expire_time"]
    except gemini.TokenMintError as e:
        if not settings().dev_return_raw_key:
            await supa.update(
                "calls",
                filters={"id": f"eq.{call['id']}"},
                patch={"status": "failed"},
            )
            raise HTTPException(502, {"code": "token_mint_failed"}) from e
        token, kind, expire = settings().gemini_api_key, "dev_raw_key", None

    return SessionResponse(
        call_id=call["id"],
        provider="gemini_live",
        model=settings().live_model,
        token=token,
        token_kind=kind,  # type: ignore[arg-type]
        expire_time=expire,
        remaining_seconds=remaining,
    )


# ─────────────────────────────────────────────────────────────
# POST /v1/calls/{call_id}/end — burn minutes, persist transcript
# ─────────────────────────────────────────────────────────────
class Turn(BaseModel):
    role: Literal["user", "assistant"]
    text: str
    t_start_ms: int = 0
    t_end_ms: int = 0


class EndCallRequest(BaseModel):
    duration_s: int = Field(ge=0, le=3 * 3600)
    turns: list[Turn] = Field(default_factory=list, max_length=2000)


@router.post("/calls/{call_id}/end")
async def end_call(
    call_id: str,
    body: EndCallRequest,
    user_id: UserId,
    background: BackgroundTasks,
) -> dict[str, Any]:
    calls = await supa.select(
        "calls", filters={"id": f"eq.{call_id}", "user_id": f"eq.{user_id}"}
    )
    if not calls:
        raise HTTPException(404, "call not found")
    if calls[0]["status"] != "active":
        return {"ok": True, "status": calls[0]["status"]}  # idempotent

    await supa.update(
        "calls",
        filters={"id": f"eq.{call_id}"},
        patch={
            "status": "ended",
            "ended_at": datetime.now(UTC).isoformat(),
            "duration_s": body.duration_s,
        },
    )
    if body.turns:
        await supa.insert(
            "transcripts",
            {"call_id": call_id, "turns": [t.model_dump() for t in body.turns]},
        )
    if body.duration_s > 0:
        await supa.insert(
            "minute_ledger",
            {
                "user_id": user_id,
                "delta_seconds": -body.duration_s,
                "reason": "call",
                "call_id": call_id,
            },
        )

    await _bump_daily_rollup(user_id, body.duration_s)

    turns = [t.model_dump() for t in body.turns]
    learner_words = sum(
        len(t["text"].split()) for t in turns if t["role"] == "user"
    )
    will_analyze = learner_words >= MIN_ANALYSIS_WORDS
    if will_analyze:
        background.add_task(_run_analysis, call_id, turns)
    return {"ok": True, "status": "ended", "analyzing": will_analyze}


async def _run_analysis(call_id: str, turns: list[dict[str, Any]]) -> None:
    try:
        report = await analysis.analyze_transcript(turns)
        await supa.insert("reports", {"call_id": call_id, **report})
        await supa.update(
            "calls",
            filters={"id": f"eq.{call_id}"},
            patch={"status": "analyzed"},
        )
        logger.info("analysis done for call %s", call_id)
    except Exception:
        # Call stays 'ended'; the app's report screen times out gracefully.
        logger.exception("analysis failed for call %s", call_id)


async def _bump_daily_rollup(user_id: str, duration_s: int) -> None:
    today = date.today().isoformat()
    rows = await supa.select(
        "user_progress",
        filters={"user_id": f"eq.{user_id}", "date": f"eq.{today}"},
    )
    prev = rows[0] if rows else {"minutes": 0, "calls": 0}
    await supa.upsert(
        "user_progress",
        {
            "user_id": user_id,
            "date": today,
            "minutes": prev["minutes"] + round(duration_s / 60),
            "calls": prev["calls"] + 1,
        },
        on_conflict="user_id,date",
    )


# ─────────────────────────────────────────────────────────────
# GET /v1/me/limits — the home screen's goal ring data
# ─────────────────────────────────────────────────────────────
@router.get("/me/limits")
async def my_limits(user_id: UserId) -> dict[str, Any]:
    tier = await _tier(user_id)
    remaining = await _remaining_seconds(user_id)
    allowance = (
        settings().premium_daily_seconds
        if tier == "premium"
        else settings().free_daily_seconds
    )
    return {
        "tier": tier,
        "daily_allowance_seconds": allowance,
        "remaining_seconds": remaining,
    }
