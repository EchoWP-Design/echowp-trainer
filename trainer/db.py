"""SQLite-Speicher. Eine Datei, keine externen Dienste."""

from __future__ import annotations

import json
import sqlite3
import threading
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator

SCHEMA = """
CREATE TABLE IF NOT EXISTS daily_metrics (
    date TEXT PRIMARY KEY,
    sleep_hours REAL,
    sleep_score REAL,
    hrv_ms REAL,
    resting_hr REAL,
    body_battery REAL,
    stress_avg REAL,
    steps INTEGER,
    garmin_readiness REAL,
    source TEXT,
    synced_at TEXT
);
CREATE TABLE IF NOT EXISTS journal (
    date TEXT PRIMARY KEY,
    mood INTEGER,
    energy INTEGER,
    soreness INTEGER,
    stress INTEGER,
    motivation INTEGER,
    weight_kg REAL,
    notes TEXT,
    food_notes TEXT,
    food_quality INTEGER,
    corrections TEXT,
    briefing_read INTEGER DEFAULT 0,
    updated_at TEXT
);
CREATE TABLE IF NOT EXISTS activities (
    id TEXT PRIMARY KEY,
    date TEXT NOT NULL,
    start_time TEXT,
    kind TEXT NOT NULL,
    name TEXT,
    duration_s REAL,
    distance_m REAL,
    avg_hr REAL,
    max_hr REAL,
    training_load REAL,
    rpe INTEGER,
    feedback TEXT,
    source TEXT
);
CREATE INDEX IF NOT EXISTS idx_activities_date ON activities(date);
CREATE TABLE IF NOT EXISTS plan_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    week_start TEXT NOT NULL,
    date TEXT NOT NULL,
    start TEXT,
    end TEXT,
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    focus TEXT,
    rpe INTEGER,
    exercises TEXT,
    status TEXT DEFAULT 'geplant'
);
CREATE INDEX IF NOT EXISTS idx_plan_date ON plan_sessions(date);
CREATE TABLE IF NOT EXISTS week_notes (
    week_start TEXT PRIMARY KEY,
    phase TEXT,
    summary TEXT,
    rationale TEXT,
    questions TEXT,
    source TEXT,
    created_at TEXT
);
CREATE TABLE IF NOT EXISTS chat (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    channel TEXT NOT NULL,
    ts TEXT NOT NULL,
    role TEXT NOT NULL,
    content TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sync_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts TEXT NOT NULL,
    source TEXT NOT NULL,
    ok INTEGER NOT NULL,
    message TEXT
);
"""

DEFAULT_SETTINGS: dict[str, Any] = {
    "goals": {"strength": 4, "cardio": 3, "march": 1},
    "max_hr": 190,
    "sleep_target_h": 8.0,
    # Freie Trainingsfenster je Wochentag (0 = Montag)
    "slots": {
        "0": [["06:30", "07:45"], ["18:00", "19:30"]],
        "1": [["06:30", "07:45"], ["18:00", "19:30"]],
        "2": [["06:30", "07:45"], ["18:00", "19:30"]],
        "3": [["06:30", "07:45"], ["18:00", "19:30"]],
        "4": [["06:30", "07:45"], ["17:00", "18:30"]],
        "5": [["08:00", "11:00"], ["16:00", "18:00"]],
        "6": [["08:00", "11:00"], ["16:00", "18:00"]],
    },
    "busy_ics_url": "",
    "preferences": (
        "Schwerpunkt Functional Fitness: Eigengewicht, Kettlebell, Gewichte. Ausdauer als "
        "Steigungsgehen auf dem Laufband. Märsche, auch mit Gewicht (Rucking), am Wochenende."
    ),
    "constraints": "Kniebeschwerden: wenig Laufen, keine Sprünge, keine tiefen Ausfallschritte.",
    "running_goal": "Langer Marsch 25 km mit 12 kg Rucksack",
    # Für den Kalorienrechner. nutrition_mode: "wissenschaft" oder "jan"
    "profile": {
        "sex": None,
        "height_cm": None,
        "birth_year": None,
        "weight_kg": None,
        "goal": "halten",
        "nutrition_mode": "wissenschaft",
    },
}


class Database:
    def __init__(self, path: Path | str):
        self.path = str(path)
        self._lock = threading.Lock()
        self._conn = sqlite3.connect(self.path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.executescript(SCHEMA)
        self._conn.commit()

    @contextmanager
    def tx(self) -> Iterator[sqlite3.Connection]:
        with self._lock:
            try:
                yield self._conn
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise

    def query(self, sql: str, params: tuple | dict = ()) -> list[dict[str, Any]]:
        with self._lock:
            return [dict(r) for r in self._conn.execute(sql, params).fetchall()]

    def one(self, sql: str, params: tuple | dict = ()) -> dict[str, Any] | None:
        rows = self.query(sql, params)
        return rows[0] if rows else None

    def upsert(self, table: str, row: dict[str, Any], key: str = "date") -> None:
        cols = list(row)
        placeholders = ",".join("?" for _ in cols)
        updates = ",".join(f"{c}=excluded.{c}" for c in cols if c != key)
        sql = (
            f"INSERT INTO {table} ({','.join(cols)}) VALUES ({placeholders}) "
            f"ON CONFLICT({key}) DO UPDATE SET {updates}"
        )
        with self.tx() as c:
            c.execute(sql, tuple(row[c_] for c_ in cols))

    # --- Einstellungen -------------------------------------------------
    def get_setting(self, key: str) -> Any:
        row = self.one("SELECT value FROM settings WHERE key=?", (key,))
        if row is None:
            return DEFAULT_SETTINGS.get(key)
        return json.loads(row["value"])

    def all_settings(self) -> dict[str, Any]:
        merged = dict(DEFAULT_SETTINGS)
        for row in self.query("SELECT key, value FROM settings"):
            merged[row["key"]] = json.loads(row["value"])
        return merged

    def set_setting(self, key: str, value: Any) -> None:
        with self.tx() as c:
            c.execute(
                "INSERT INTO settings(key, value) VALUES (?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                (key, json.dumps(value)),
            )
