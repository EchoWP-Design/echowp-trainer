import base64
import io
import json
import time
import urllib.error
from datetime import date

import pytest

from trainer.garmin import personal_api
from trainer.garmin.base import SourceError
from trainer.garmin.personal_api import PersonalApiSource, find_value, parse_personal_daily


def _jwt(exp: float) -> str:
    payload = base64.urlsafe_b64encode(json.dumps({"exp": exp}).encode()).decode().rstrip("=")
    return f"h.{payload}.s"


class FakeResp(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


def test_find_value_nested():
    assert find_value({"a": [{"b": {"restingHeartRate": 49}}]}, ("restingHeartRate",)) == 49
    assert find_value({"x": {"overall": {"value": 81}}}, ("overall",)) == 81


def test_parse_personal_daily():
    m = parse_personal_daily(
        date(2026, 11, 22),
        sleep={"dailySleepDTO": {"sleepTimeSeconds": 25200, "sleepScores": {"overall": {"value": 77}}}},
        hrv={"hrvSummary": {"lastNightAvg": 61}},
        summary=[{"calendarDate": "2026-11-21", "restingHeartRate": 60},
                 {"calendarDate": "2026-11-22", "restingHeartRate": 50, "totalSteps": 8000, "averageStressLevel": 25}],
        body_battery=[{"calendarDate": "2026-11-22", "highestValue": 88}],
    )
    assert (m.sleep_hours, m.sleep_score, m.hrv_ms, m.resting_hr, m.steps, m.body_battery) == (7.0, 77, 61, 50, 8000, 88)


def test_token_exchange_and_requests(tmp_path, monkeypatch):
    calls = []
    token = _jwt(time.time() + 24 * 3600)

    def fake_urlopen(req, timeout=0):
        calls.append((req.get_method(), req.full_url, req.headers.get("Authorization")))
        if req.full_url.endswith(personal_api.TOKEN_PATH):
            return FakeResp(token.encode())
        if "activities/search" in req.full_url:
            return FakeResp(json.dumps([{"activityId": 7, "startTimeLocal": "2026-11-22 07:00:00",
                                         "activityType": {"typeKey": "walking"}, "duration": 4000}]).encode())
        return FakeResp(b"{}")

    monkeypatch.setattr(personal_api.urllib.request, "urlopen", fake_urlopen)
    src = PersonalApiSource("secret-key-123456", tmp_path / "tok.json")
    acts = src.fetch_activities(date(2026, 11, 20), date(2026, 11, 22))
    assert acts[0].kind == "gehen" and acts[0].source == "garmin-personal-api"
    assert calls[0][2] == "ApiKey secret-key-123456"
    assert calls[1][2] == f"Bearer {token}"
    # Token wird gecacht und von einer neuen Instanz wiederverwendet
    calls.clear()
    PersonalApiSource("secret-key-123456", tmp_path / "tok.json").get("/x")
    assert len(calls) == 1 and calls[0][2] == f"Bearer {token}"


def test_rejected_key(tmp_path, monkeypatch):
    def fake_urlopen(req, timeout=0):
        raise urllib.error.HTTPError(req.full_url, 401, "no", {}, None)

    monkeypatch.setattr(personal_api.urllib.request, "urlopen", fake_urlopen)
    with pytest.raises(SourceError, match="abgelehnt"):
        PersonalApiSource("bad", tmp_path / "t.json").fetch_daily(date(2026, 11, 22))
