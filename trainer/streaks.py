"""Gewohnheiten und Streaks (Gamification) sowie Wochenziele."""

from __future__ import annotations

from datetime import date, timedelta

DAILY_HABITS = [
    ("garmin", "Garmin synchronisiert"),
    ("sleep7", "Mehr als 7 h Schlaf"),
    ("journal", "Journal ausgefüllt"),
    ("training", "Bewegt (Training)"),
]


def daily_grid(today: date, metrics: dict[str, dict], journal: dict[str, dict],
               activities: dict[str, list], days: int = 28) -> dict:
    grid: dict[str, list] = {k: [] for k, _ in DAILY_HABITS}
    dates = [(today - timedelta(days=i)).isoformat() for i in range(days - 1, -1, -1)]
    for d in dates:
        m = metrics.get(d) or {}
        j = journal.get(d) or {}
        corr = j.get("corrections") or {}
        sleep = corr.get("sleep_hours") or m.get("sleep_hours")
        grid["garmin"].append(bool(m) and m.get("source") not in (None, "", "manuell"))
        grid["sleep7"].append(bool(sleep and sleep >= 7))
        grid["journal"].append(bool(j.get("mood") or j.get("energy") or j.get("notes")))
        grid["training"].append(bool(activities.get(d)))
    streaks = {k: _streak(v) for k, v in grid.items()}
    return {
        "dates": dates,
        "habits": [{"key": k, "label": label, "days": grid[k], "streak": streaks[k]} for k, label in DAILY_HABITS],
    }


def _streak(values: list[bool]) -> int:
    """Zählt von heute rückwärts. Ein noch offener heutiger Tag bricht nichts."""
    n = 0
    vals = list(values)
    if vals and not vals[-1]:
        vals = vals[:-1]
    for v in reversed(vals):
        if not v:
            break
        n += 1
    return n


def week_goals(week_acts: list[dict], goals: dict) -> list[dict]:
    strength = sum(1 for a in week_acts if a["kind"] == "kraft")
    # Langer Marsch: Gehen/Wandern ab 60 Minuten
    marches = [a for a in week_acts if a["kind"] == "gehen" and (a.get("duration_s") or 0) >= 3600]
    cardio = sum(1 for a in week_acts if a["kind"] in ("lauf", "cardio"))
    return [
        {"key": "strength", "label": "Functional/Kraft", "done": strength, "goal": goals.get("strength", 0)},
        {"key": "cardio", "label": "Ausdauer", "done": cardio, "goal": goals.get("cardio", 0)},
        {"key": "march", "label": "Langer Marsch", "done": len(marches),
         "goal": goals.get("march", goals.get("longrun", 0))},
    ]
