"""Post-call transcript analysis (PLAN.md §6).

Provider-neutral by design: `analyze_transcript` takes turns, returns the
report dict that maps 1:1 onto the `reports` table. Currently backed by
Gemini Flash (free tier); swapping to Claude later means changing only
`_call_model`.
"""

import asyncio
import json
from typing import Any

import httpx

from .config import settings

_BASE = "https://generativelanguage.googleapis.com"

# The preview model intermittently 503s ("high demand") and sometimes hangs;
# retry those, fail fast on real errors (400s besides 429).
_RETRIABLE = {429, 500, 503, 504}


async def _generate_with(
    model: str, body: dict[str, Any], *, timeout: float, attempts: int
) -> dict[str, Any]:
    last: Exception = AnalysisError("no attempts made")
    for i in range(attempts):
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                resp = await client.post(
                    f"{_BASE}/v1beta/{model}:generateContent",
                    params={"key": settings().gemini_api_key},
                    json=body,
                )
            if resp.status_code == 200:
                return resp.json()
            last = AnalysisError(f"{resp.status_code}: {resp.text[:300]}")
            if resp.status_code not in _RETRIABLE:
                break
        except httpx.HTTPError as e:
            last = AnalysisError(f"network: {e!r}")
        if i < attempts - 1:
            await asyncio.sleep(2.0 * (i + 1))
    raise last


async def _generate(
    body: dict[str, Any], *, timeout: float = 60, attempts: int = 3
) -> dict[str, Any]:
    try:
        return await _generate_with(
            settings().analysis_model, body, timeout=timeout, attempts=attempts
        )
    except AnalysisError as e:
        # Quota exhausted or model retired → the fallback's separate quota
        # bucket keeps reports landing.
        if not str(e).startswith(("429", "404")):
            raise
        return await _generate_with(
            settings().analysis_fallback_model, body, timeout=timeout, attempts=2
        )

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
- hinglish: moments where the learner switched into Hindi or Hinglish
  ("matlab", "haan", "yaar", "kya bolte hain", whole Hindi clauses). Count
  the switches and give up to 3 examples: "said" quotes the mixed sentence
  verbatim, "english" is how the whole thought sounds in natural English.
  Established Indian English ("prepone", "do the needful") is NOT Hinglish.
  If they never switched, count 0 with no examples.
- Scores 0-100. Calibrate: 40-60 beginner, 60-75 improving, 75-85 good,
  85+ near-fluent. overall is a weighted feel, not an average.
- If the learner spoke very little, score what you can and say so in
  focus_points.
- memory: 2-4 sentences of notes the coach will read before the NEXT call,
  written in third person. Capture personal facts the learner shared (job,
  city, family, plans, upcoming events), the main topics discussed, and
  anything worth following up on ("has an interview next week"). Only facts
  from this transcript — never invent.
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
        "memory",
        "hinglish",
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
        "hinglish": {
            "type": "OBJECT",
            "required": ["count", "examples"],
            "properties": {
                "count": {"type": "INTEGER"},
                "examples": {
                    "type": "ARRAY",
                    "items": {
                        "type": "OBJECT",
                        "required": ["said", "english"],
                        "properties": {
                            "said": {"type": "STRING"},
                            "english": {"type": "STRING"},
                        },
                    },
                },
            },
        },
        "memory": {
            "type": "STRING",
            "description": "Third-person notes for the coach before the next "
            "call: personal facts shared, topics discussed, follow-ups.",
        },
    },
}


class AnalysisError(Exception):
    pass


def _candidate_text(data: dict[str, Any]) -> str:
    """Concatenated text parts of the first candidate.

    Thinking models may emit thought parts before (or instead of) the text
    part, so grabbing parts[0]["text"] blindly is flaky.
    """
    parts = data["candidates"][0]["content"]["parts"]
    return "".join(
        p.get("text", "") for p in parts if p.get("text") and not p.get("thought")
    )


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
    data = await _generate(body)
    try:
        return json.loads(_candidate_text(data))
    except (KeyError, IndexError, json.JSONDecodeError) as e:
        raise AnalysisError(f"bad model output: {e}") from e


def _clamp(v: Any, lo: int = 0, hi: int = 100) -> int:
    try:
        return max(lo, min(hi, int(v)))
    except (TypeError, ValueError):
        return lo


def compute_metrics(turns: list[dict[str, Any]]) -> dict[str, Any]:
    """Talk-time and pace, computed deterministically from turn timestamps.

    Timestamps come from when transcription fragments reached the app, so
    they track speech loosely; per-turn floors (max realistic speaking rate)
    keep a burst of late fragments from reading as impossibly fast speech.
    """
    user_ms = coach_ms = user_words = 0
    for t in turns:
        dur = max(0, int(t.get("t_end_ms") or 0) - int(t.get("t_start_ms") or 0))
        words = len((t.get("text") or "").split())
        if t.get("role") == "user":
            user_words += words
            user_ms += max(dur, int(words / 3.3 * 1000))  # ≤ ~200 wpm
        else:
            coach_ms += max(dur, int(words / 2.5 * 1000))  # TTS ≈ 150 wpm
    total = user_ms + coach_ms
    if total == 0 or user_words == 0:
        return {}
    return {
        "user_talk_seconds": round(user_ms / 1000),
        "coach_talk_seconds": round(coach_ms / 1000),
        "talk_share_pct": round(user_ms * 100 / total),
        "wpm": _clamp(round(user_words / (user_ms / 60000)), 40, 220),
        "user_words": user_words,
    }


async def analyze_transcript(turns: list[dict[str, Any]]) -> dict[str, Any]:
    """Returns a dict shaped for the `reports` table (minus call_id)."""
    report = await _call_model(_format_transcript(turns))
    scores = report.get("scores") or {}
    hinglish = report.get("hinglish") or {}
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
        "hinglish": {
            "count": _clamp(hinglish.get("count"), 0, 99),
            "examples": (hinglish.get("examples") or [])[:3],
        },
        "metrics": compute_metrics(turns),
        "memory": str(report.get("memory") or "")[:600],
    }


async def week_line(stats: dict[str, Any]) -> str:
    """One warm coach-voice sentence about the learner's week; '' on failure."""
    prompt = (
        "You are the learner's English-speaking coach. Write exactly ONE "
        "warm, specific sentence (max 25 words) summarizing their week of "
        "practice, speaking directly to them as 'you'. Mention the most "
        "notable number or trend. No emoji, no greeting, no quotes.\n"
        f"Their week: {json.dumps(stats)}"
    )
    body = {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        # No maxOutputTokens: the model thinks before answering and the
        # thinking spends from the same budget — a cap truncates the sentence.
        "generationConfig": {"temperature": 0.6},
    }
    try:
        text = _candidate_text(await _generate(body, timeout=25, attempts=2))
        return " ".join(text.split()).strip()[:200]
    except Exception:  # noqa: BLE001 — the card just falls back to stats
        return ""
