"""Post-call transcript analysis (PLAN.md §6).

Provider-neutral by design: `analyze_transcript` takes turns, returns the
report dict that maps 1:1 onto the `reports` table. Currently backed by
Gemini Flash (free tier); swapping to Claude later means changing only
`_call_model`.
"""

import json
from typing import Any

import httpx

from .config import settings

_BASE = "https://generativelanguage.googleapis.com"

_SYSTEM = """You are an expert English-speaking coach reviewing a phone-call
transcript between a learner (role "user") and an AI coach (role "assistant").
The learner is typically an Indian English speaker preparing for interviews,
IELTS, or daily conversation.

Analyze ONLY the learner's speech. Be encouraging but honest — this report
should feel like a supportive coach, never a pedantic teacher.

Rules:
- grammar_issues: at most 3, ONLY the highest-impact ones. "said" must quote
  the learner verbatim, "better" is the natural correction, "why" is one
  short, plain-language explanation of the rule. Skip filler-word issues here.
- vocab_suggestions: at most 3 word/phrase upgrades from things they said.
- filler_words: count occurrences of um/uh/like/actually/basically/you know
  in the learner's turns, and list which ones they used.
- focus_points: exactly 2-3 short imperative phrases for the next call,
  e.g. "Use past tense for finished actions".
- Scores 0-100. Calibrate: 40-60 beginner, 60-75 improving, 75-85 good,
  85+ near-fluent. overall is a weighted feel, not an average.
- If the learner spoke very little, score what you can and say so in
  focus_points.
- Never invent quotes that are not in the transcript."""

_SCHEMA = {
    "type": "OBJECT",
    "required": [
        "overall",
        "scores",
        "grammar_issues",
        "vocab_suggestions",
        "filler_words",
        "focus_points",
        "headline",
    ],
    "properties": {
        "overall": {"type": "INTEGER"},
        "headline": {
            "type": "STRING",
            "description": "One warm sentence summarizing the call, e.g. "
            "'Your best interview answers yet — past tense still slips.'",
        },
        "scores": {
            "type": "OBJECT",
            "required": ["grammar", "fluency", "vocabulary", "confidence"],
            "properties": {
                "grammar": {"type": "INTEGER"},
                "fluency": {"type": "INTEGER"},
                "vocabulary": {"type": "INTEGER"},
                "confidence": {"type": "INTEGER"},
            },
        },
        "grammar_issues": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "required": ["said", "better", "why"],
                "properties": {
                    "said": {"type": "STRING"},
                    "better": {"type": "STRING"},
                    "why": {"type": "STRING"},
                },
            },
        },
        "vocab_suggestions": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "required": ["used", "better"],
                "properties": {
                    "used": {"type": "STRING"},
                    "better": {"type": "STRING"},
                },
            },
        },
        "filler_words": {
            "type": "OBJECT",
            "required": ["count", "words"],
            "properties": {
                "count": {"type": "INTEGER"},
                "words": {"type": "ARRAY", "items": {"type": "STRING"}},
            },
        },
        "focus_points": {"type": "ARRAY", "items": {"type": "STRING"}},
    },
}


class AnalysisError(Exception):
    pass


def _format_transcript(turns: list[dict[str, Any]]) -> str:
    lines = []
    for t in turns:
        speaker = "LEARNER" if t.get("role") == "user" else "COACH"
        text = (t.get("text") or "").strip()
        if text:
            lines.append(f"{speaker}: {text}")
    return "\n".join(lines)


async def _call_model(transcript: str) -> dict[str, Any]:
    body = {
        "systemInstruction": {"parts": [{"text": _SYSTEM}]},
        "contents": [{"role": "user", "parts": [{"text": transcript}]}],
        "generationConfig": {
            "responseMimeType": "application/json",
            "responseSchema": _SCHEMA,
            "temperature": 0.3,
        },
    }
    async with httpx.AsyncClient(timeout=60) as client:
        resp = await client.post(
            f"{_BASE}/v1beta/{settings().analysis_model}:generateContent",
            params={"key": settings().gemini_api_key},
            json=body,
        )
    if resp.status_code != 200:
        raise AnalysisError(f"{resp.status_code}: {resp.text[:300]}")
    data = resp.json()
    try:
        text = data["candidates"][0]["content"]["parts"][0]["text"]
        return json.loads(text)
    except (KeyError, IndexError, json.JSONDecodeError) as e:
        raise AnalysisError(f"bad model output: {e}") from e


def _clamp(v: Any, lo: int = 0, hi: int = 100) -> int:
    try:
        return max(lo, min(hi, int(v)))
    except (TypeError, ValueError):
        return lo


async def analyze_transcript(turns: list[dict[str, Any]]) -> dict[str, Any]:
    """Returns a dict shaped for the `reports` table (minus call_id)."""
    report = await _call_model(_format_transcript(turns))
    scores = report.get("scores") or {}
    return {
        "model": settings().analysis_model,
        "overall": _clamp(report.get("overall")),
        "scores": {
            "grammar": _clamp(scores.get("grammar")),
            "fluency": _clamp(scores.get("fluency")),
            "vocabulary": _clamp(scores.get("vocabulary")),
            "confidence": _clamp(scores.get("confidence")),
            "headline": str(report.get("headline") or "")[:200],
        },
        "grammar_issues": (report.get("grammar_issues") or [])[:3],
        "vocab_suggestions": (report.get("vocab_suggestions") or [])[:3],
        "filler_words": report.get("filler_words")
        or {"count": 0, "words": []},
        "focus_points": (report.get("focus_points") or [])[:3],
    }
