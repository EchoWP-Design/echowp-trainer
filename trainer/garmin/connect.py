"""Garmin Connect über die inoffizielle Bibliothek `garminconnect`.

Garmin bietet Privatpersonen keine offizielle API an. Diese Quelle meldet sich
mit deinen Garmin-Connect-Zugangsdaten an (wie die Garmin-App) und speichert
danach nur noch Tokens im Datenordner. Funktioniert, kann aber brechen, wenn
Garmin intern etwas ändert. Für den Notfall gibt es den FIT-Import.
"""

from __future__ import annotations

import logging
from datetime import date
from pathlib import Path
from typing import Any

from .base import Activity, DailyMetrics, SourceError, map_kind

log = logging.getLogger(__name__)


def _get(d: Any, *path: str) -> Any:
    for key in path:
        if not isinstance(d, dict):
            return None
        d = d.get(key)
    return d


def _num(v: Any) -> float | None:
    try:
        return None if v is None else float(v)
    except (TypeError, ValueError):
        return None


def parse_daily(
    day: date,
    stats: dict | None,
    sleep: dict | None,
    hrv: dict | None,
    readiness: list | dict | None,
) -> DailyMetrics:
    """Wandelt Garmin-Connect-Antworten in DailyMetrics um (ohne Netzwerk testbar)."""
    m = DailyMetrics(date=day.isoformat(), source="garmin-connect")
    sleep_dto = _get(sleep, "dailySleepDTO") or {}
    secs = _num(sleep_dto.get("sleepTimeSeconds"))
    if secs:
        m.sleep_hours = round(secs / 3600, 2)
    m.sleep_score = _num(_get(sleep_dto, "sleepScores", "overall", "value"))
    m.hrv_ms = _num(_get(hrv, "hrvSummary", "lastNightAvg"))
    stats = stats or {}
    m.resting_hr = _num(stats.get("restingHeartRate"))
    m.stress_avg = _num(stats.get("averageStressLevel"))
    steps = _num(stats.get("totalSteps"))
    m.steps = int(steps) if steps is not None else None
    m.body_battery = _num(
        stats.get("bodyBatteryAtWakeTime")
        or stats.get("bodyBatteryHighestValue")
        or stats.get("bodyBatteryMostRecentValue")
    )
    if isinstance(readiness, list) and readiness:
        m.garmin_readiness = _num(readiness[0].get("score"))
    elif isinstance(readiness, dict):
        m.garmin_readiness = _num(readiness.get("score"))
    if m.stress_avg is not None and m.stress_avg < 0:
        m.stress_avg = None  # Garmin liefert -1/-2 für "keine Daten"
    return m


def parse_activity(raw: dict) -> Activity:
    start = raw.get("startTimeLocal") or ""
    return Activity(
        id=f"gc-{raw.get('activityId')}",
        date=start[:10],
        start_time=start[11:16] or None,
        kind=map_kind(_get(raw, "activityType", "typeKey")),
        name=raw.get("activityName") or "",
        duration_s=_num(raw.get("duration")),
        distance_m=_num(raw.get("distance")),
        avg_hr=_num(raw.get("averageHR")),
        max_hr=_num(raw.get("maxHR")),
        training_load=_num(raw.get("activityTrainingLoad")),
        source="garmin-connect",
    )


class GarminConnectSource:
    name = "garmin-connect"

    def __init__(self, email: str | None, password: str | None, tokenstore: Path):
        self.email = email
        self.password = password
        self.tokenstore = tokenstore
        self._client = None

    def _login(self):
        if self._client is not None:
            return self._client
        try:
            from garminconnect import Garmin
        except ImportError as exc:  # pragma: no cover
            raise SourceError("Paket 'garminconnect' fehlt (pip install garminconnect)") from exc

        self.tokenstore.mkdir(parents=True, exist_ok=True)
        client = Garmin(self.email, self.password)
        try:
            # Nutzt gespeicherte Tokens; nur wenn keine da sind, die Zugangsdaten
            client.login(str(self.tokenstore))
        except Exception as exc:
            raise SourceError(
                "Garmin-Anmeldung fehlgeschlagen. Einmal 'python -m trainer.garmin_login' "
                f"ausführen (auch für Zwei-Faktor-Codes). Details: {exc}"
            ) from exc
        try:
            client.client.dump(str(self.tokenstore))
        except Exception:  # Tokens speichern ist optional
            pass
        self._client = client
        return client

    def _safe(self, fn, *args):
        try:
            return fn(*args)
        except Exception as exc:  # einzelne Endpunkte dürfen fehlen
            log.warning("Garmin-Abfrage %s fehlgeschlagen: %s", getattr(fn, "__name__", fn), exc)
            return None

    def fetch_daily(self, day: date) -> DailyMetrics:
        c = self._login()
        iso = day.isoformat()
        return parse_daily(
            day,
            stats=self._safe(c.get_stats, iso),
            sleep=self._safe(c.get_sleep_data, iso),
            hrv=self._safe(c.get_hrv_data, iso),
            readiness=self._safe(c.get_training_readiness, iso),
        )

    def fetch_activities(self, start: date, end: date) -> list[Activity]:
        c = self._login()
        raw = self._safe(c.get_activities_by_date, start.isoformat(), end.isoformat()) or []
        return [parse_activity(r) for r in raw if r.get("activityId")]
