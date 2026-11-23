"""Import von FIT-Dateien (Aktivitäten direkt von der Uhr oder aus Garmin Connect
exportiert) sowie der Tages-JSON-Dateien aus dem Garmin-Datenexport (DSGVO-Export).

Das ist der Weg ohne Online-Zugang: Uhr per USB anschließen, Ordner
GARMIN/Activity öffnen, .fit-Dateien hochladen.
"""

from __future__ import annotations

import hashlib
import io
import json
from datetime import datetime

from .base import Activity, DailyMetrics, SourceError, map_kind


def parse_fit(data: bytes, filename: str = "") -> Activity:
    try:
        import fitdecode
    except ImportError as exc:  # pragma: no cover
        raise SourceError("Paket 'fitdecode' fehlt (pip install fitdecode)") from exc

    session: dict = {}
    sport = None
    try:
        with fitdecode.FitReader(io.BytesIO(data)) as fit:
            for frame in fit:
                if not isinstance(frame, fitdecode.FitDataMessage):
                    continue
                if frame.name == "session" and not session:
                    session = {f.name: f.value for f in frame.fields}
                elif frame.name == "sport" and sport is None:
                    sport = frame.get_value("sport", fallback=None)
    except Exception as exc:
        raise SourceError(f"FIT-Datei '{filename}' konnte nicht gelesen werden: {exc}") from exc

    if not session:
        raise SourceError(f"FIT-Datei '{filename}' enthält keine Aktivität (keine session)")

    start: datetime | None = session.get("start_time")
    sport = sport or session.get("sport")
    sub = session.get("sub_sport")
    garmin_type = str(sport or "")
    if garmin_type == "training" and str(sub) == "strength_training":
        garmin_type = "strength_training"
    if garmin_type == "running" and str(sub) == "treadmill":
        garmin_type = "treadmill_running"

    digest = hashlib.sha1(data).hexdigest()[:16]
    return Activity(
        id=f"fit-{digest}",
        date=start.date().isoformat() if start else "",
        start_time=start.strftime("%H:%M") if start else None,
        kind=map_kind(garmin_type),
        name=filename.rsplit("/", 1)[-1] or garmin_type,
        duration_s=_f(session.get("total_timer_time") or session.get("total_elapsed_time")),
        distance_m=_f(session.get("total_distance")),
        avg_hr=_f(session.get("avg_heart_rate")),
        max_hr=_f(session.get("max_heart_rate")),
        training_load=_f(session.get("training_load_peak") or session.get("total_training_effect")),
        source="fit-import",
    )


def _f(v) -> float | None:
    try:
        return None if v is None else float(v)
    except (TypeError, ValueError):
        return None


def parse_export_json(data: bytes) -> list[DailyMetrics]:
    """Liest Tageswerte aus dem Garmin-Datenexport.

    Unterstützt die Dateien `*_sleepData.json` (Liste mit calendarDate,
    deepSleepSeconds, lightSleepSeconds, remSleepSeconds, sleepScores) und
    `UDSFile_*.json` (calendarDate, restingHeartRate, totalSteps, bodyBattery ...).
    """
    try:
        payload = json.loads(data)
    except json.JSONDecodeError as exc:
        raise SourceError(f"Keine gültige JSON-Datei: {exc}") from exc
    if isinstance(payload, dict):
        payload = [payload]
    out: dict[str, DailyMetrics] = {}
    for item in payload:
        if not isinstance(item, dict):
            continue
        day = item.get("calendarDate")
        if isinstance(day, dict):  # ältere Exporte
            day = day.get("date")
        if not day:
            continue
        day = str(day)[:10]
        m = out.setdefault(day, DailyMetrics(date=day, source="garmin-export"))
        secs = sum(
            item.get(k) or 0 for k in ("deepSleepSeconds", "lightSleepSeconds", "remSleepSeconds")
        )
        if secs:
            m.sleep_hours = round(secs / 3600, 2)
        score = (item.get("sleepScores") or {}).get("overallScore")
        if score is not None:
            m.sleep_score = _f(score)
        if item.get("restingHeartRate") is not None:
            m.resting_hr = _f(item["restingHeartRate"])
        if item.get("totalSteps") is not None:
            m.steps = int(item["totalSteps"])
        stress = (item.get("allDayStress") or {}).get("aggregatorList")
        if isinstance(stress, list):
            total = next((s for s in stress if s.get("type") == "TOTAL"), None)
            if total and total.get("averageStressLevel", -1) >= 0:
                m.stress_avg = _f(total["averageStressLevel"])
        bb = item.get("bodyBattery") or {}
        stat_list = bb.get("bodyBatteryStatList") if isinstance(bb, dict) else None
        if isinstance(stat_list, list):
            high = next((s for s in stat_list if s.get("bodyBatteryStatType") == "HIGHEST"), None)
            if high:
                m.body_battery = _f(high.get("statsValue"))
    return [m for m in out.values() if m.has_data()]
