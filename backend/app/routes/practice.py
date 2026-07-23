"""Practice drills generated from the learner's own recent mistakes.

Completes the deliberate-practice loop (BUSINESS.md §2): call → report →
drills → next call. Exercises are *new* sentences exhibiting the learner's
error patterns — practicing the pattern, not memorizing the correction.
"""

import json
import logging
from typing import Any

import httpx
from fastapi import APIRouter

from .. import supa
from ..auth import UserId
from ..config import settings

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/v1")

_SCHEMA = {
    "type": "OBJECT",
    "required": ["exercises"],
    "properties": {
        "exercises": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "required": ["kind", "prompt", "answer", "why"],
                "properties": {
                    "kind": {
                        "type": "STRING",
                        "enum": ["fix", "choose", "upgrade"],
                    },
                    "prompt": {"type": "STRING"},
                    "answer": {"type": "STRING"},
                    "why": {"type": "STRING"},
                },
            },
        },
    },
}

_SYSTEM = """You create short practice drills for an Indian English learner,
based on the exact mistakes they made in recent voice calls.

Rules:
- 6 exercises total, each targeting one of their real error patterns.
- kind "fix": prompt is a NEW incorrect sentence (same error pattern, different
  words than their original) with the instruction "Fix this sentence:". answer
  is the corrected sentence.
- kind "choose": prompt offers two versions A) and B) of a sentence, one
  correct; answer names the correct one and repeats it.
- kind "upgrade": prompt asks for a stronger word/phrase for a weak one they
  used; answer gives 1-2 better options in a sample sentence.
- why: one short, plain-language rule reminder.
- Keep every sentence conversational and workplace/daily-life relevant.
- Do NOT reuse their exact original sentences — new sentences, same patterns."""


@router.get("/practice")
async def practice_pack(user_id: UserId) -> dict[str, Any]:
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
    if not issues and not vocab:
        return {"exercises": [], "source_mistakes": [], "source_vocab": []}

    material = {
        "their_mistakes": issues[:10],
        "their_weak_vocab": vocab[:8],
        "current_focus": list(dict.fromkeys(focus))[:5],
    }
    body = {
        "systemInstruction": {"parts": [{"text": _SYSTEM}]},
        "contents": [
            {
                "role": "user",
                "parts": [{"text": json.dumps(material, ensure_ascii=False)}],
            }
        ],
        "generationConfig": {
            "responseMimeType": "application/json",
            "responseSchema": _SCHEMA,
            "temperature": 0.6,
        },
    }
    exercises: list[dict[str, Any]] = []
    try:
        async with httpx.AsyncClient(timeout=45) as client:
            resp = await client.post(
                "https://generativelanguage.googleapis.com/v1beta/"
                f"{settings().analysis_model}:generateContent",
                params={"key": settings().gemini_api_key},
                json=body,
            )
        if resp.status_code == 200:
            text = resp.json()["candidates"][0]["content"]["parts"][0]["text"]
            exercises = (json.loads(text).get("exercises") or [])[:8]
        else:
            logger.error("practice generation %s: %s", resp.status_code, resp.text[:200])
    except Exception:
        logger.exception("practice generation failed for %s", user_id)

    return {
        # Review material straight from their reports, even if generation
        # failed — the app always has something to show.
        "source_mistakes": issues[:6],
        "source_vocab": vocab[:6],
        "exercises": exercises,
    }
