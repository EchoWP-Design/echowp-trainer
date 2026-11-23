from datetime import date, datetime
from zoneinfo import ZoneInfo

from trainer.db import DEFAULT_SETTINGS
from trainer.planner import build_week, determine_phase

MONDAY = date(2026, 11, 30)


def test_week_matches_goals_and_is_knee_friendly():
    p = build_week(MONDAY, DEFAULT_SETTINGS, 72, [], (114, 133))
    kinds = [s.kind for s in p.sessions]
    assert kinds.count("kraft") == DEFAULT_SETTINGS["goals"]["strength"]
    assert kinds.count("cardio") + kinds.count("intervall") == DEFAULT_SETTINGS["goals"]["cardio"]
    assert kinds.count("marsch") == 1
    marsch = next(s for s in p.sessions if s.kind == "marsch")
    assert date.fromisoformat(marsch.date).weekday() in (5, 6)
    text = " ".join(s.title + s.focus + " ".join(e["name"] for e in s.exercises) for s in p.sessions).lower()
    for banned in ("lauf ", "sprung", "box jump", "jumping"):
        assert banned not in text
    assert "laufband" in text and "kettlebell" in text


def test_busy_calendar_blocks_slot():
    tz = ZoneInfo("Europe/Berlin")
    busy = [(datetime(2026, 11, 30, 17, 30, tzinfo=tz), datetime(2026, 11, 30, 21, 0, tzinfo=tz), "Elternabend")]
    p = build_week(MONDAY, DEFAULT_SETTINGS, 72, busy)
    monday_evening = [s for s in p.sessions if s.date == "2026-11-30" and s.start >= "17:00"]
    assert not monday_evening


def test_training_blocker_can_be_overwritten():
    tz = ZoneInfo("Europe/Berlin")
    busy = [(datetime(2026, 11, 30, 18, 0, tzinfo=tz), datetime(2026, 11, 30, 19, 30, tzinfo=tz), "Training (Blocker)")]
    p = build_week(MONDAY, DEFAULT_SETTINGS, 72, busy)
    assert any(s.date == "2026-11-30" and s.start == "18:00" for s in p.sessions)


def test_low_readiness_gives_relief_week():
    phase, volume, rpe = determine_phase(MONDAY, 45)
    assert phase == "Entlastung" and volume < 1 and rpe < 0
    p = build_week(MONDAY, DEFAULT_SETTINGS, 45)
    assert not any(s.kind == "intervall" for s in p.sessions)
