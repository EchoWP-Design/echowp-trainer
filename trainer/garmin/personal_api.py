"""Offizielle Garmin Connect Personal API (seit Herbst 2026).

Der empfohlene Weg: Du erstellst in Garmin Connect Web unter
Einstellungen → Personal API Key einen Schlüssel
(https://connect.garmin.com/app/settings/personalApiToken) und trägst ihn als
GARMIN_PERSONAL_API_KEY ein. Die App tauscht ihn gegen ein Zugriffstoken
(24 h gültig) und liest damit Schlaf, HRV, Tageswerte und Aktivitäten.

Endpunkte laut Swagger-Doku und Garmins Beispielclient
(github.com/garmin/connect-personal-api-python). Die Antwortfelder sind dort
nicht vollständig beschrieben; die Auswertung sucht deshalb tolerant nach den
üblichen Garmin-Feldnamen. Mit `python -m trainer.garmin_probe` speicherst du
die Rohdaten eines Tages, falls ein Wert fehlt und die Zuordnung angepasst
werden muss.
"""

from __future__ import annotations

import base64
import json
import logging
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, timedelta
from pathlib import Path
from typing import Any

from .base import Activity, DailyMetrics, SourceError
from .connect import parse_activity

log = logging.getLogger(__name__)

BASE_URL = "https://personal.connectapi.garmin.com"
TOKEN_PATH = "/personalapitoken-service/personal-api/personal-api-key/token"
REFRESH_WINDOW_S = 3600


def _jwt_exp(token: str) -> float:
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        return float(json.loads(base64.urlsafe_b64decode(payload))["exp"])
    except Exception:
        return time.time() + 23 * 3600


def find_value(data: Any, keys: tuple[str, ...]) -> float | None:
    """Sucht rekursiv den ersten Zahlenwert unter einem der Schlüssel."""
    if isinstance(data, dict):
        for k in keys:
            v = data.get(k)
            if isinstance(v, (int, float)) and not isinstance(v, bool):
                return float(v)
            if isinstance(v, dict) and isinstance(v.get("value"), (int, float)):
                return float(v["value"])
        for v in data.values():
            found = find_value(v, keys)
            if found is not None:
                return found
    elif isinstance(data, list):
        for item in data:
            found = find_value(item, keys)
            if found is not None:
                return found
    return None


def pick_day(data: Any, iso: str) -> Any:
    """Aus Listen-Antworten den Eintrag für einen Kalendertag wählen."""
    if isinstance(data, dict):
        for key in ("dailySummaries", "summaries", "values", "data", "items"):
            if isinstance(data.get(key), list):
                return pick_day(data[key], iso)
        return data
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict) and str(item.get("calendarDate", item.get("date", "")))[:10] == iso:
                return item
        return None
    return data


def parse_personal_daily(day: date, sleep: Any, hrv: Any, summary: Any, body_battery: Any) -> DailyMetrics:
    iso = day.isoformat()
    m = DailyMetrics(date=iso, source="garmin-personal-api")
    secs = find_value(sleep, ("sleepTimeSeconds",))
    if secs:
        m.sleep_hours = round(secs / 3600, 2)
    m.sleep_score = find_value(find_value_dict(sleep, "sleepScores") or sleep, ("overall", "overallScore", "sleepScore"))
    m.hrv_ms = find_value(hrv, ("lastNightAvg", "lastNightAverage"))
    s = pick_day(summary, iso)
    m.resting_hr = find_value(s, ("restingHeartRate", "restingHeartRateValue", "restingValue"))
    stress = find_value(s, ("averageStressLevel", "avgStressLevel", "overallStressLevel"))
    m.stress_avg = stress if stress is not None and stress >= 0 else None
    steps = find_value(s, ("totalSteps", "steps"))
    m.steps = int(steps) if steps is not None else None
    bb = pick_day(body_battery, iso)
    m.body_battery = find_value(s, ("bodyBatteryAtWakeTime",)) or find_value(
        bb, ("bodyBatteryAtWakeTime", "atWakeTime", "startOfDayValue", "highestValue", "bodyBatteryHighestValue",
             "highest", "max"))
    return m


def find_value_dict(data: Any, key: str) -> Any:
    if isinstance(data, dict):
        if isinstance(data.get(key), dict):
            return data[key]
        for v in data.values():
            r = find_value_dict(v, key)
            if r is not None:
                return r
    elif isinstance(data, list):
        for v in data:
            r = find_value_dict(v, key)
            if r is not None:
                return r
    return None


class PersonalApiSource:
    name = "garmin-personal-api"

    def __init__(self, api_key: str, cache_file: Path, base_url: str = BASE_URL, timeout: float = 30):
        self.api_key = api_key.strip()
        self.cache_file = cache_file
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self._token: str | None = None
        self._exp = 0.0

    # ---------- Authentifizierung ----------
    def _load_cache(self) -> None:
        try:
            data = json.loads(self.cache_file.read_text())
            if data.get("key_tail") == self.api_key[-6:]:
                self._token, self._exp = data["access_token"], float(data["expires_at"])
        except Exception:
            pass

    def token(self, force: bool = False) -> str:
        if not force and self._token is None:
            self._load_cache()
        if not force and self._token and self._exp - time.time() > REFRESH_WINDOW_S:
            return self._token
        req = urllib.request.Request(
            self.base_url + TOKEN_PATH, method="POST",
            headers={"Accept": "*/*", "Authorization": f"ApiKey {self.api_key}"},
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:  # noqa: S310
                token = resp.read().decode().strip()
        except urllib.error.HTTPError as exc:
            if exc.code in (401, 403):
                raise SourceError(
                    "Garmin Personal API Key wurde abgelehnt (abgelaufen oder gelöscht?). "
                    "Neuen Key unter connect.garmin.com/app/settings/personalApiToken erstellen."
                ) from exc
            raise SourceError(f"Garmin-Token konnte nicht geholt werden: HTTP {exc.code}") from exc
        except urllib.error.URLError as exc:
            raise SourceError(f"Garmin nicht erreichbar: {exc.reason}") from exc
        self._token, self._exp = token, _jwt_exp(token)
        try:
            self.cache_file.parent.mkdir(parents=True, exist_ok=True)
            self.cache_file.write_text(json.dumps(
                {"access_token": token, "expires_at": self._exp, "key_tail": self.api_key[-6:]}))
            self.cache_file.chmod(0o600)
        except OSError:
            pass
        return token

    def get(self, path: str, params: dict | None = None, _retry: bool = True) -> Any:
        url = self.base_url + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers={"Accept": "application/json",
                                                   "Authorization": f"Bearer {self.token()}"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:  # noqa: S310
                body = resp.read()
                return json.loads(body) if body else None
        except urllib.error.HTTPError as exc:
            if exc.code == 401 and _retry:
                self.token(force=True)
                return self.get(path, params, _retry=False)
            if exc.code in (204, 404):
                return None
            raise SourceError(f"Garmin-Abfrage {path} fehlgeschlagen: HTTP {exc.code}") from exc
        except urllib.error.URLError as exc:
            raise SourceError(f"Garmin nicht erreichbar: {exc.reason}") from exc

    def _safe(self, path: str, params: dict | None = None) -> Any:
        try:
            return self.get(path, params)
        except SourceError as exc:
            if "abgelehnt" in str(exc) or "nicht erreichbar" in str(exc):
                raise
            log.warning("%s", exc)
            return None

    # ---------- Daten ----------
    def raw_day(self, day: date) -> dict:
        iso = day.isoformat()
        return {
            "sleep": self._safe("/sleep-service/sleep/dailySleep", {"date": iso}),
            "hrv": self._safe(f"/hrv-service/hrv/{iso}"),
            "summary": self._safe("/usersummary-service/v2/dailysummaries", {"startDate": iso, "endDate": iso}),
            "body_battery": self._safe("/wellness-service/wellness/bodyBattery/reports/daily",
                                       {"startDate": iso, "endDate": iso}),
        }

    def fetch_daily(self, day: date) -> DailyMetrics:
        raw = self.raw_day(day)
        return parse_personal_daily(day, raw["sleep"], raw["hrv"], raw["summary"], raw["body_battery"])

    def fetch_activities(self, start: date, end: date) -> list[Activity]:
        out: list[Activity] = []
        offset = 0
        while True:
            page = self._safe("/activitylist-service/activities/search/activities", {
                "start": offset, "limit": 50,
                "startDate": start.isoformat(), "endDate": (end + timedelta(days=0)).isoformat(),
            })
            items = page if isinstance(page, list) else (page or {}).get("activityList") or []
            out += [parse_activity(a) for a in items if isinstance(a, dict) and a.get("activityId")]
            if len(items) < 50 or offset > 500:
                break
            offset += 50
        for a in out:
            a.source = self.name
        return out
