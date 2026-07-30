"""Streak logic for "Today's 5" (BUSINESS.md §5).

A day is *active* if the learner made a call (user_progress) or completed
the daily pack (daily_packs.completed_at). The streak walks back from
today (IST days everywhere); one missed day per ISO week is forgiven —
the free rest day — so a single slip doesn't zero weeks of momentum.
"""

import logging
from datetime import UTC, date, datetime, timedelta
from typing import Any

from . import supa

logger = logging.getLogger(__name__)

_IST = timedelta(hours=5, minutes=30)


def ist_today() -> date:
    return (datetime.now(UTC) + _IST).date()


async def active_dates(user_id: str, days: int = 90) -> set[str]:
    since = (ist_today() - timedelta(days=days)).isoformat()
    prog = await supa.select(
        "user_progress",
        columns="date,calls,minutes",
        filters={"user_id": f"eq.{user_id}", "date": f"gte.{since}"},
    )
    packs = await supa.select(
        "daily_packs",
        columns="date,completed_at",
        filters={"user_id": f"eq.{user_id}", "date": f"gte.{since}"},
    )
    active = {
        p["date"]
        for p in prog
        if (p.get("calls") or 0) > 0 or (p.get("minutes") or 0) > 0
    }
    active |= {p["date"] for p in packs if p.get("completed_at")}
    return active


def compute_streak(active: set[str], today: date) -> int:
    """Consecutive active days ending today-ish, with weekly rest days.

    Today itself never breaks the streak (the day isn't over), it only
    adds when already active. Earlier gaps are forgiven once per ISO week.
    """
    streak = 1 if today.isoformat() in active else 0
    rest_spent: set[tuple[int, int]] = set()
    d = today - timedelta(days=1)
    for _ in range(365):
        if d.isoformat() in active:
            streak += 1
        else:
            week = d.isocalendar()[:2]
            if week in rest_spent:
                break
            rest_spent.add(week)
        d -= timedelta(days=1)
    return streak


async def current_streak(user_id: str) -> int:
    """Compute the streak and keep the streaks table in sync (best effort)."""
    active = await active_dates(user_id)
    streak = compute_streak(active, ist_today())
    try:
        rows = await supa.select(
            "streaks", filters={"user_id": f"eq.{user_id}"}, columns="longest"
        )
        longest = max(streak, int(rows[0]["longest"]) if rows else 0)
        await supa.upsert(
            "streaks",
            {
                "user_id": user_id,
                "current": streak,
                "longest": longest,
                "last_active_date": max(active) if active else None,
            },
            on_conflict="user_id",
        )
    except Exception:  # noqa: BLE001 — the cached row is cosmetic
        logger.exception("streak sync failed for %s", user_id)
    return streak


def week_activity(active: set[str], today: date) -> list[dict[str, Any]]:
    """Last-7-days activity map for UI dots/grids."""
    out = []
    for i in range(6, -1, -1):
        d = (today - timedelta(days=i)).isoformat()
        out.append({"date": d, "active": d in active})
    return out
