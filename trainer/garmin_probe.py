"""Speichert die Garmin-Rohdaten eines Tages zur Fehlersuche.

    python -m trainer.garmin_probe 2026-11-22

Legt data/garmin-probe-<datum>.json an. Damit lässt sich prüfen, welche Felder
Garmin liefert, wenn ein Wert in der App fehlt. Die Datei enthält
Gesundheitsdaten: nicht öffentlich teilen.
"""

from __future__ import annotations

import json
import sys
from datetime import date

from .config import Settings
from .garmin import make_source


def main() -> None:
    day = date.fromisoformat(sys.argv[1]) if len(sys.argv) > 1 else date.today()
    s = Settings.load()
    src = make_source(s)
    if src is None or not hasattr(src, "raw_day"):
        sys.exit("Rohdaten-Abruf gibt es nur für die Personal API (GARMIN_PERSONAL_API_KEY setzen).")
    raw = src.raw_day(day)
    raw["activities"] = src._safe("/activitylist-service/activities/search/activities",
                                  {"start": 0, "limit": 5, "startDate": day.isoformat(), "endDate": day.isoformat()})
    raw["parsed"] = src.fetch_daily(day).as_row()
    out = s.data_dir / f"garmin-probe-{day}.json"
    out.write_text(json.dumps(raw, indent=2, ensure_ascii=False))
    print(f"Gespeichert: {out}")
    print(json.dumps(raw["parsed"], indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
