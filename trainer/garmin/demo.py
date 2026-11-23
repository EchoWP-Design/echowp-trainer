"""Demo-Daten zum Ausprobieren ohne Uhr (TRAINER_DEMO=on)."""

from __future__ import annotations

import random
from datetime import date, timedelta

from .base import KIND_CARDIO, KIND_MOBILITY, KIND_STRENGTH, KIND_WALK, Activity, DailyMetrics


class DemoSource:
    name = "demo"

    def _rng(self, day: date) -> random.Random:
        return random.Random(day.toordinal())

    def fetch_daily(self, day: date) -> DailyMetrics:
        r = self._rng(day)
        return DailyMetrics(
            date=day.isoformat(),
            sleep_hours=round(r.uniform(5.8, 8.6), 2),
            sleep_score=round(r.uniform(55, 92)),
            hrv_ms=round(r.uniform(42, 68)),
            resting_hr=round(r.uniform(48, 58)),
            body_battery=round(r.uniform(45, 100)),
            stress_avg=round(r.uniform(18, 45)),
            steps=r.randint(4000, 16000),
            garmin_readiness=round(r.uniform(35, 95)),
            source="demo",
        )

    def fetch_activities(self, start: date, end: date) -> list[Activity]:
        out = []
        d = start
        while d <= end:
            r = self._rng(d)
            wd = d.weekday()
            if wd in (0, 1, 3, 4):
                out.append(Activity(
                    id=f"demo-{d}-k", date=d.isoformat(), start_time="18:10", kind=KIND_STRENGTH,
                    name=["Kettlebell Ganzkörper", "Functional Push", "", "Functional Pull", "Hüfte & Rumpf"][wd],
                    duration_s=r.randint(50, 70) * 60, avg_hr=r.randint(110, 130), source="demo",
                ))
            if wd in (1, 3, 5):
                out.append(Activity(
                    id=f"demo-{d}-c", date=d.isoformat(), start_time="06:40", kind=KIND_CARDIO,
                    name="Laufband Steigung", duration_s=r.randint(35, 45) * 60,
                    distance_m=r.uniform(3200, 4200), avg_hr=r.randint(118, 132), source="demo",
                ))
            if wd == 6:
                km = r.uniform(9, 13)
                out.append(Activity(
                    id=f"demo-{d}-m", date=d.isoformat(), start_time="08:30", kind=KIND_WALK,
                    name="Rucking", duration_s=km * 600, distance_m=km * 1000,
                    avg_hr=r.randint(112, 125), source="demo",
                ))
            if wd == 5:
                out.append(Activity(
                    id=f"demo-{d}-y", date=d.isoformat(), start_time="17:00", kind=KIND_MOBILITY,
                    name="Mobility", duration_s=1500, source="demo",
                ))
            d += timedelta(days=1)
        return out
