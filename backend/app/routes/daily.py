""""Today's 5" — the daily practice pack (BUSINESS.md §5, Sprint 1).

One generated pack per user per IST day, cached in daily_packs so it's
stable all day and completion syncs across devices. Personalized from
recent reports when they exist, level/goal otherwise; a static seed pack
guarantees the day is never empty even if generation fails.
"""

import json
import logging
from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from .. import analysis, streaks, supa
from ..auth import UserId

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/v1")

_SCHEMA = {
    "type": "OBJECT",
    "required": ["items"],
    "properties": {
        "items": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "required": ["kind", "prompt", "options", "answer", "why"],
                "properties": {
                    "kind": {
                        "type": "STRING",
                        "enum": ["mcq", "rewrite", "speak"],
                    },
                    "prompt": {"type": "STRING"},
                    "options": {"type": "ARRAY", "items": {"type": "STRING"}},
                    "answer": {"type": "STRING"},
                    "why": {"type": "STRING"},
                },
            },
        },
    },
}

_SYSTEM = """You create "Today's 5" — five quick daily drills for an Indian
English learner. Total time ~4 minutes. Conversational, workplace and
daily-life sentences only.

Exactly 5 items, in this order:
1. kind "mcq" — grammar: an everyday sentence with a blank or choice.
   prompt states the task, options has exactly 3 choices, answer is the
   exact text of the correct option.
2. kind "mcq" — another grammar pattern (different error family).
3. kind "rewrite" — prompt is "Fix this sentence: <incorrect sentence>",
   options is empty, answer is the corrected sentence.
4. kind "mcq" — word choice: which option sounds most natural/professional.
5. kind "speak" — a speaking prompt they answer OUT LOUD in 2-3 sentences
   ("Describe your typical Monday", "Convince me to watch your favourite
   film"). options is empty, answer is a strong model answer (2-3
   sentences) at their level.

- why: one short, plain-language explanation (for speak: one tip).
- If learner mistakes are provided, target those exact error patterns with
  NEW sentences — never reuse their originals.
- Match difficulty to their level; keep it winnable and warm."""

# Never let the day be empty: a solid generic pack if generation fails.
_SEED: list[dict[str, Any]] = [
    {
        "kind": "mcq",
        "prompt": "Pick the correct sentence:",
        "options": [
            "I am working here since three years.",
            "I have been working here for three years.",
            "I work here since three years.",
        ],
        "answer": "I have been working here for three years.",
        "why": "Durations that continue into the present take the present "
        "perfect continuous with 'for'.",
    },
    {
        "kind": "mcq",
        "prompt": "Yesterday I ___ my manager about the deadline.",
        "options": ["tell", "told", "have told"],
        "answer": "told",
        "why": "A finished action at a stated past time takes simple past.",
    },
    {
        "kind": "rewrite",
        "prompt": "Fix this sentence: She don't have no time for the meeting.",
        "options": [],
        "answer": "She doesn't have any time for the meeting.",
        "why": "Third person takes 'doesn't', and English avoids double "
        "negatives — use 'any', not 'no'.",
    },
    {
        "kind": "mcq",
        "prompt": "Which sounds most professional in a standup?",
        "options": [
            "I did the needful on the bug.",
            "I fixed the bug and deployed the patch.",
            "The bug work is done from my side.",
        ],
        "answer": "I fixed the bug and deployed the patch.",
        "why": "Specific verbs (fixed, deployed) sound clearer and more "
        "confident than vague phrases.",
    },
    {
        "kind": "speak",
        "prompt": "Say it out loud: describe your typical workday morning "
        "in 2-3 sentences.",
        "options": [],
        "answer": "I usually start my day around nine with a quick look at "
        "my messages. After that, I plan my main tasks and join the team "
        "standup. By ten, I'm deep into focused work.",
        "why": "Keep verbs in simple present for routines, and link "
        "sentences with 'after that' and 'by ten' to sound fluent.",
    },
]


async def _material(user_id: str) -> dict[str, Any]:
    profile = await supa.select(
        "profiles", filters={"id": f"eq.{user_id}"}, columns="level,goal"
    )
    rows = await supa.select(
        "reports",
        columns="grammar_issues,vocab_suggestions,focus_points,"
        "calls!inner(user_id)",
        filters={
            "calls.user_id": f"eq.{user_id}",
            "order": "created_at.desc",
            "limit": "5",
        },
    )
    issues: list[dict[str, Any]] = []
    vocab: list[dict[str, Any]] = []
    focus: list[str] = []
    for r in rows:
        issues += r.get("grammar_issues") or []
        vocab += r.get("vocab_suggestions") or []
        focus += r.get("focus_points") or []
    return {
        "level": profile[0]["level"] if profile else "intermediate",
        "goal": profile[0]["goal"] if profile else "daily",
        "their_mistakes": issues[:8],
        "their_weak_vocab": vocab[:6],
        "current_focus": list(dict.fromkeys(focus))[:4],
    }


async def _generate_items(user_id: str) -> list[dict[str, Any]]:
    body = {
        "systemInstruction": {"parts": [{"text": _SYSTEM}]},
        "contents": [
            {
                "role": "user",
                "parts": [
                    {
                        "text": json.dumps(
                            await _material(user_id), ensure_ascii=False
                        )
                    }
                ],
            }
        ],
        "generationConfig": {
            "responseMimeType": "application/json",
            "responseSchema": _SCHEMA,
            "temperature": 0.7,
        },
    }
    try:
        data = await analysis._generate(body, timeout=45)
        items = json.loads(analysis._candidate_text(data)).get("items") or []
        # Sanity: exactly 5 usable items or fall back.
        good = [
            i
            for i in items
            if i.get("kind") in {"mcq", "rewrite", "speak"}
            and i.get("prompt")
            and i.get("answer")
        ][:5]
        if len(good) == 5:
            return good
        logger.warning("daily pack for %s came back short; using seed", user_id)
    except Exception:
        logger.exception("daily pack generation failed for %s", user_id)
    return _SEED


@router.get("/practice/daily")
async def daily_pack(user_id: UserId) -> dict[str, Any]:
    today = streaks.ist_today().isoformat()
    rows = await supa.select(
        "daily_packs",
        filters={"user_id": f"eq.{user_id}", "date": f"eq.{today}"},
    )
    if rows:
        pack = rows[0]
    else:
        items = await _generate_items(user_id)
        pack = await supa.insert(
            "daily_packs",
            {"user_id": user_id, "date": today, "items": items},
        )
    streak = await streaks.current_streak(user_id)
    active = await streaks.active_dates(user_id, days=8)
    return {
        "date": today,
        "items": pack["items"],
        "done": pack.get("done") or [],
        "completed": pack.get("completed_at") is not None,
        "streak": streak,
        "week": streaks.week_activity(active, streaks.ist_today()),
    }


class CompleteRequest(BaseModel):
    index: int = Field(ge=0, le=19)


@router.post("/practice/daily/complete")
async def complete_item(body: CompleteRequest, user_id: UserId) -> dict[str, Any]:
    today = streaks.ist_today().isoformat()
    rows = await supa.select(
        "daily_packs",
        filters={"user_id": f"eq.{user_id}", "date": f"eq.{today}"},
    )
    if not rows:
        raise HTTPException(404, "no pack for today")
    pack = rows[0]
    items = pack["items"] or []
    if body.index >= len(items):
        raise HTTPException(422, "index out of range")

    done = sorted({*(pack.get("done") or []), body.index})
    patch: dict[str, Any] = {"done": done}
    just_finished = len(done) >= len(items) and not pack.get("completed_at")
    if just_finished:
        from datetime import UTC, datetime

        patch["completed_at"] = datetime.now(UTC).isoformat()
    await supa.update(
        "daily_packs",
        filters={"user_id": f"eq.{user_id}", "date": f"eq.{today}"},
        patch=patch,
    )
    streak = await streaks.current_streak(user_id)
    return {
        "done": done,
        "completed": bool(pack.get("completed_at")) or just_finished,
        "streak": streak,
    }
