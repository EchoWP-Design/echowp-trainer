import json
from datetime import date

import pytest

from trainer.garmin.base import SourceError
from trainer.garmin.connect import parse_activity, parse_daily
from trainer.garmin.fit_import import parse_export_json, parse_fit


def test_parse_daily_from_connect_payloads():
    m = parse_daily(
        date(2026, 11, 22),
        stats={"restingHeartRate": 51, "averageStressLevel": 28, "totalSteps": 9876, "bodyBatteryAtWakeTime": 82},
        sleep={"dailySleepDTO": {"sleepTimeSeconds": 27000, "sleepScores": {"overall": {"value": 84}}}},
        hrv={"hrvSummary": {"lastNightAvg": 58}},
        readiness=[{"score": 77}],
    )
    assert (m.sleep_hours, m.sleep_score, m.hrv_ms, m.resting_hr) == (7.5, 84, 58, 51)
    assert (m.body_battery, m.steps, m.garmin_readiness) == (82, 9876, 77)


def test_parse_daily_tolerates_missing_and_negative():
    m = parse_daily(date(2026, 11, 22), {"averageStressLevel": -1}, None, None, None)
    assert m.stress_avg is None and not m.has_data()


def test_parse_activity_maps_kinds():
    a = parse_activity({"activityId": 1, "startTimeLocal": "2026-11-22 08:30:00",
                        "activityType": {"typeKey": "hiking"}, "duration": 5400, "distance": 9000})
    assert a.kind == "gehen" and a.date == "2026-11-22" and a.start_time == "08:30"
    assert parse_activity({"activityId": 2, "startTimeLocal": "2026-11-22 18:00:00",
                           "activityType": {"typeKey": "strength_training"}}).kind == "kraft"


def test_export_json():
    data = json.dumps([
        {"calendarDate": "2026-11-20", "deepSleepSeconds": 5400, "lightSleepSeconds": 14400,
         "remSleepSeconds": 7200, "sleepScores": {"overallScore": 81}},
        {"calendarDate": "2026-11-21", "restingHeartRate": 52, "totalSteps": 12000},
    ]).encode()
    days = {m.date: m for m in parse_export_json(data)}
    assert days["2026-11-20"].sleep_hours == 7.5 and days["2026-11-20"].sleep_score == 81
    assert days["2026-11-21"].resting_hr == 52


def test_invalid_fit_raises_source_error():
    with pytest.raises(SourceError):
        parse_fit(b"not a fit file", "x.fit")
