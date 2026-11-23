"""Gemeinsame Datentypen und die Schnittstelle für alle Garmin-Datenquellen.

Jede Quelle (Garmin Connect, FIT-Import, offizielle Health API, Demo) liefert
dieselben zwei Dinge: Tageswerte (Schlaf, HRV, Ruhepuls, Body Battery ...) und
Aktivitäten. Der Rest der App kennt nur diese Typen.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import date
from typing import Protocol

# Einheitliche Sportarten in der App
KIND_RUN = "lauf"
KIND_STRENGTH = "kraft"
KIND_CARDIO = "cardio"
KIND_MOBILITY = "mobility"
KIND_WALK = "gehen"
KIND_OTHER = "sonstiges"

_GARMIN_KIND_MAP = {
    "running": KIND_RUN,
    "trail_running": KIND_RUN,
    "treadmill_running": KIND_RUN,
    "track_running": KIND_RUN,
    "street_running": KIND_RUN,
    "strength_training": KIND_STRENGTH,
    "training": KIND_STRENGTH,
    "cycling": KIND_CARDIO,
    "indoor_cycling": KIND_CARDIO,
    "road_biking": KIND_CARDIO,
    "mountain_biking": KIND_CARDIO,
    "virtual_ride": KIND_CARDIO,
    "lap_swimming": KIND_CARDIO,
    "open_water_swimming": KIND_CARDIO,
    "swimming": KIND_CARDIO,
    "rowing": KIND_CARDIO,
    "indoor_rowing": KIND_CARDIO,
    "elliptical": KIND_CARDIO,
    "hiit": KIND_CARDIO,
    "cardio": KIND_CARDIO,
    "yoga": KIND_MOBILITY,
    "pilates": KIND_MOBILITY,
    "flexibility_training": KIND_MOBILITY,
    "breathwork": KIND_MOBILITY,
    "walking": KIND_WALK,
    "hiking": KIND_WALK,
    "rucking": KIND_WALK,
    "treadmill_walking": KIND_WALK,
    "indoor_walking": KIND_WALK,
    "kettlebell": KIND_STRENGTH,
    "functional_training": KIND_STRENGTH,
    "generic": KIND_OTHER,
}


def map_kind(garmin_type: str | None) -> str:
    if not garmin_type:
        return KIND_OTHER
    return _GARMIN_KIND_MAP.get(garmin_type.lower(), KIND_OTHER)


@dataclass
class DailyMetrics:
    date: str
    sleep_hours: float | None = None
    sleep_score: float | None = None
    hrv_ms: float | None = None
    resting_hr: float | None = None
    body_battery: float | None = None
    stress_avg: float | None = None
    steps: int | None = None
    garmin_readiness: float | None = None
    source: str = ""

    def as_row(self) -> dict:
        return asdict(self)

    def has_data(self) -> bool:
        return any(
            v is not None
            for k, v in asdict(self).items()
            if k not in ("date", "source")
        )


@dataclass
class Activity:
    id: str
    date: str
    kind: str
    name: str = ""
    start_time: str | None = None
    duration_s: float | None = None
    distance_m: float | None = None
    avg_hr: float | None = None
    max_hr: float | None = None
    training_load: float | None = None
    source: str = ""
    extra: dict = field(default_factory=dict)

    def as_row(self) -> dict:
        row = asdict(self)
        row.pop("extra")
        return row


class GarminSource(Protocol):
    """Schnittstelle, die jede Datenquelle erfüllt."""

    name: str

    def fetch_daily(self, day: date) -> DailyMetrics: ...

    def fetch_activities(self, start: date, end: date) -> list[Activity]: ...


class SourceError(RuntimeError):
    """Verbindungs- oder Anmeldefehler einer Quelle, mit deutscher Meldung."""
