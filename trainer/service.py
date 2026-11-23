"""Fachlogik zwischen Datenbank, Garmin-Quellen, Score, Planer und Coach."""

from __future__ import annotations

import io
import json
import logging
import zipfile
from datetime import date, datetime, timedelta
from typing import Any

from . import nutrition, running, streaks
from .calendar_ics import fetch_busy
from .coach import Coach
from .config import Settings
from .db import Database
from .garmin import SourceError, make_source
from .garmin.base import Activity, DailyMetrics
from .garmin.fit_import import parse_export_json, parse_fit
from .planner import build_week, week_start_of
from .readiness import Readiness, compute

log = logging.getLogger(__name__)
ENDURANCE = ("lauf", "cardio")
# Gewichtung der Trainingsstunden für den PAL: Gehen/Marsch und Mobility
# verbrauchen pro Stunde weniger als Kraft- oder Ausdauertraining.
KIND_WEIGHT = {"kraft": 1.0, "cardio": 1.0, "lauf": 1.0, "gehen": 0.8, "mobility": 0.3, "sonstiges": 0.8}


class TrainerService:
    def __init__(self, settings: Settings, db: Database | None = None, coach: Coach | None = None,
                 source=None):
        self.settings = settings
        self.db = db or Database(settings.db_path)
        self.coach = coach or Coach(settings.coach_enabled, settings.anthropic_model)
        self.source = source if source is not None else make_source(settings)

    # ---------------- Speichern ----------------
    def store_metrics(self, m: DailyMetrics) -> None:
        row = m.as_row()
        row["synced_at"] = datetime.now().isoformat(timespec="seconds")
        # vorhandene Werte nicht mit None überschreiben
        existing = self.db.one("SELECT * FROM daily_metrics WHERE date=?", (m.date,)) or {}
        for k, v in list(row.items()):
            if v is None and existing.get(k) is not None:
                row[k] = existing[k]
        self.db.upsert("daily_metrics", row)

    def store_activity(self, a: Activity) -> None:
        row = a.as_row()
        existing = self.db.one("SELECT rpe, feedback FROM activities WHERE id=?", (a.id,))
        row["rpe"] = existing["rpe"] if existing else None
        row["feedback"] = existing["feedback"] if existing else None
        self.db.upsert("activities", row, key="id")

    def log_sync(self, source: str, ok: bool, message: str) -> None:
        with self.db.tx() as c:
            c.execute("INSERT INTO sync_log(ts, source, ok, message) VALUES (?,?,?,?)",
                      (datetime.now().isoformat(timespec="seconds"), source, int(ok), message))

    # ---------------- Synchronisation ----------------
    def sync(self, days: int = 3, activity_days: int = 14, today: date | None = None) -> dict:
        today = today or date.today()
        if self.source is None:
            msg = ("Keine Garmin-Verbindung eingerichtet. GARMIN_EMAIL/GARMIN_PASSWORD setzen "
                   "oder FIT-Dateien importieren.")
            self.log_sync("keine", False, msg)
            return {"ok": False, "message": msg}
        try:
            n_days = 0
            for i in range(days):
                m = self.source.fetch_daily(today - timedelta(days=i))
                if m.has_data():
                    self.store_metrics(m)
                    n_days += 1
            acts = self.source.fetch_activities(today - timedelta(days=activity_days), today)
            for a in acts:
                self.store_activity(a)
            msg = f"{n_days} Tage und {len(acts)} Aktivitäten aktualisiert."
            self.log_sync(self.source.name, True, msg)
            return {"ok": True, "message": msg}
        except SourceError as exc:
            self.log_sync(self.source.name, False, str(exc))
            return {"ok": False, "message": str(exc)}
        except Exception as exc:  # Netzwerk, Garmin-Änderungen ...
            log.exception("Sync fehlgeschlagen")
            self.log_sync(getattr(self.source, "name", "?"), False, str(exc))
            return {"ok": False, "message": f"Synchronisation fehlgeschlagen: {exc}"}

    def import_files(self, files: list[tuple[str, bytes]]) -> dict:
        acts = days = 0
        errors: list[str] = []

        def handle(name: str, data: bytes) -> None:
            nonlocal acts, days
            lower = name.lower()
            if lower.endswith(".zip"):
                with zipfile.ZipFile(io.BytesIO(data)) as z:
                    for info in z.infolist():
                        if not info.is_dir() and info.file_size < 50_000_000:
                            handle(info.filename, z.read(info))
            elif lower.endswith(".fit"):
                self.store_activity(parse_fit(data, name))
                acts += 1
            elif lower.endswith(".json") and ("sleep" in lower or "uds" in lower):
                for m in parse_export_json(data):
                    self.store_metrics(m)
                    days += 1

        for name, data in files:
            try:
                handle(name, data)
            except (SourceError, zipfile.BadZipFile, ValueError) as exc:
                errors.append(f"{name}: {exc}")
        msg = f"{acts} Aktivitäten und {days} Tageswerte importiert."
        self.log_sync("import", not errors or bool(acts or days), msg + (f" Fehler: {len(errors)}" if errors else ""))
        return {"ok": not errors, "message": msg, "errors": errors[:20]}

    # ---------------- Lesen ----------------
    def metrics_map(self, start: date, end: date) -> dict[str, dict]:
        rows = self.db.query("SELECT * FROM daily_metrics WHERE date BETWEEN ? AND ?",
                             (start.isoformat(), end.isoformat()))
        return {r["date"]: r for r in rows}

    def journal_entry(self, d: str) -> dict | None:
        j = self.db.one("SELECT * FROM journal WHERE date=?", (d,))
        if j:
            j["corrections"] = json.loads(j["corrections"]) if j.get("corrections") else {}
        return j

    def journal_map(self, start: date, end: date) -> dict[str, dict]:
        rows = self.db.query("SELECT * FROM journal WHERE date BETWEEN ? AND ?", (start.isoformat(), end.isoformat()))
        for r in rows:
            r["corrections"] = json.loads(r["corrections"]) if r.get("corrections") else {}
        return {r["date"]: r for r in rows}

    def activities(self, start: date, end: date) -> list[dict]:
        return self.db.query(
            "SELECT * FROM activities WHERE date BETWEEN ? AND ? ORDER BY date DESC, start_time DESC",
            (start.isoformat(), end.isoformat()),
        )

    def readiness_for(self, d: date) -> Readiness:
        iso = d.isoformat()
        metrics = self.db.one("SELECT * FROM daily_metrics WHERE date=?", (iso,))
        history = self.db.query(
            "SELECT * FROM daily_metrics WHERE date < ? ORDER BY date DESC LIMIT 7", (iso,))
        return compute(metrics, self.journal_entry(iso), history, self.db.get_setting("sleep_target_h") or 8)

    def readiness_trend(self, end: date, days: int = 14) -> list[dict]:
        out = []
        for i in range(days - 1, -1, -1):
            d = end - timedelta(days=i)
            r = self.readiness_for(d)
            out.append({"date": d.isoformat(), "score": r.score})
        return out

    def avg_readiness(self, end: date, days: int = 7) -> float | None:
        scores = [p["score"] for p in self.readiness_trend(end, days) if p["score"] is not None]
        return sum(scores) / len(scores) if scores else None

    def latest_weight(self, before: date) -> float | None:
        row = self.db.one("SELECT weight_kg FROM journal WHERE weight_kg IS NOT NULL AND date <= ? "
                          "ORDER BY date DESC LIMIT 1", (before.isoformat(),))
        if row:
            return row["weight_kg"]
        profile = self.db.get_setting("profile") or {}
        return profile.get("weight_kg")

    def training_load(self, d: date) -> dict:
        acts = self.activities(d - timedelta(days=27), d)
        hours = sum((a.get("duration_s") or 0) * KIND_WEIGHT.get(a["kind"], 0.8) for a in acts) / 3600 / 4
        endurance = sum((a.get("duration_s") or 0) * (0.5 if a["kind"] == "gehen" else 1)
                        for a in acts if a["kind"] in ENDURANCE + ("gehen",)) / 3600 / 4
        planned_today = self.db.query("SELECT start, end FROM plan_sessions WHERE date=?", (d.isoformat(),))
        today_h = sum(_minutes(p["start"], p["end"]) for p in planned_today) / 60
        done_today = sum((a.get("duration_s") or 0) for a in acts if a["date"] == d.isoformat()) / 3600
        return {"hours_week": round(hours, 1), "endurance_hours_week": round(endurance, 1),
                "hours_today": round(max(today_h, done_today), 2)}

    def nutrition_for(self, d: date) -> dict | None:
        weight = self.latest_weight(d)
        if not weight:
            return None
        t = nutrition.calculate(weight, self.db.get_setting("profile") or {}, self.training_load(d))
        return t.as_dict()

    def running_profile(self, d: date) -> dict:
        runs = self.db.query("SELECT * FROM activities WHERE kind='lauf' AND date <= ? ORDER BY date DESC LIMIT 20",
                             (d.isoformat(),))
        walks = self.db.query("SELECT * FROM activities WHERE kind='gehen' AND date BETWEEN ? AND ? "
                              "ORDER BY date DESC", ((d - timedelta(days=27)).isoformat(), d.isoformat()))
        return running.profile(runs, self.db.get_setting("max_hr") or 190, walks)

    def week_sessions(self, week_start: date) -> list[dict]:
        rows = self.db.query("SELECT * FROM plan_sessions WHERE week_start=? ORDER BY date, start",
                             (week_start.isoformat(),))
        for r in rows:
            r["exercises"] = json.loads(r["exercises"]) if r.get("exercises") else []
        return rows

    def week_note(self, week_start: date) -> dict | None:
        n = self.db.one("SELECT * FROM week_notes WHERE week_start=?", (week_start.isoformat(),))
        if n:
            n["questions"] = json.loads(n["questions"]) if n.get("questions") else []
        return n

    # ---------------- Dashboard ----------------
    def dashboard(self, d: date) -> dict:
        iso = d.isoformat()
        r = self.readiness_for(d)
        metrics = self.db.one("SELECT * FROM daily_metrics WHERE date=?", (iso,))
        j = self.journal_entry(iso)
        ws = week_start_of(d)
        sessions = self.week_sessions(ws)
        today_sessions = [s for s in sessions if s["date"] == iso]
        briefing = self.db.get_setting(f"briefing:{iso}")
        from .coach import rule_briefing

        if not briefing or briefing.get("score") != r.score:
            briefing = {**rule_briefing(r, today_sessions), "score": r.score}
        week_acts = self.activities(ws, ws + timedelta(days=6))
        start28 = d - timedelta(days=27)
        acts28: dict[str, list] = {}
        for a in self.activities(start28, d):
            acts28.setdefault(a["date"], []).append(a)
        last_sync = self.db.one("SELECT * FROM sync_log ORDER BY id DESC LIMIT 1")
        weight_today = j.get("weight_kg") if j else None
        return {
            "date": iso,
            "readiness": r.as_dict(),
            "metrics": metrics,
            "journal": j,
            "briefing": briefing,
            "ritual": [
                {"key": "garmin", "label": "Garmin-Daten da", "done": bool(metrics)},
                {"key": "weight", "label": "Gewicht eingetragen", "done": bool(weight_today)},
                {"key": "journal", "label": "Journal ausgefüllt", "done": bool(j and (j.get("mood") or j.get("energy")))},
                {"key": "briefing", "label": "Briefing gelesen", "done": bool(j and j.get("briefing_read"))},
            ],
            "today": today_sessions,
            "week_goals": streaks.week_goals(week_acts, self.db.get_setting("goals") or {}),
            "streaks": streaks.daily_grid(d, self.metrics_map(start28, d), self.journal_map(start28, d), acts28),
            "running": self.running_profile(d),
            "nutrition": self.nutrition_for(d),
            "trend": self.readiness_trend(d),
            "activities": self.activities(d - timedelta(days=6), d),
            "last_sync": last_sync,
            "coach_enabled": self.coach.enabled,
            "live_source": getattr(self.source, "name", None),
        }

    def refresh_briefing(self, d: date) -> dict:
        iso = d.isoformat()
        r = self.readiness_for(d)
        today_sessions = [s for s in self.week_sessions(week_start_of(d)) if s["date"] == iso]
        b = self.coach.briefing(self.context(d), r, today_sessions)
        b["score"] = r.score
        self.db.set_setting(f"briefing:{iso}", b)
        return b

    # ---------------- Journal ----------------
    def save_journal(self, d: str, data: dict) -> dict:
        allowed = {"mood", "energy", "soreness", "stress", "motivation", "weight_kg", "notes",
                   "food_notes", "food_quality", "corrections", "briefing_read"}
        existing = self.journal_entry(d) or {"date": d}
        row = {k: existing.get(k) for k in allowed}
        row.update({k: v for k, v in data.items() if k in allowed})
        row["corrections"] = json.dumps({k: v for k, v in (row.get("corrections") or {}).items()
                                         if v not in (None, "")})
        row["briefing_read"] = int(bool(row.get("briefing_read")))
        row["date"] = d
        row["updated_at"] = datetime.now().isoformat(timespec="seconds")
        self.db.upsert("journal", row)
        return self.journal_entry(d)

    def activity_feedback(self, activity_id: str, rpe: int | None, feedback: str | None) -> None:
        with self.db.tx() as c:
            c.execute("UPDATE activities SET rpe=?, feedback=? WHERE id=?", (rpe, feedback, activity_id))

    # ---------------- Woche ----------------
    def plan_week(self, week_start: date, instruction: str | None = None) -> dict:
        settings = self.db.all_settings()
        busy = []
        if settings.get("busy_ics_url"):
            try:
                busy = fetch_busy(settings["busy_ics_url"], week_start, week_start + timedelta(days=6),
                                  self.settings.timezone)
            except Exception as exc:
                log.warning("Kalender konnte nicht gelesen werden: %s", exc)
        avg = self.avg_readiness(date.today())
        base = build_week(week_start, settings, avg, busy, self.running_profile(date.today()).get("zone2_hr"))
        ctx = self.context(date.today(), days=30)
        ctx["busy"] = [{"start": b[0].isoformat(), "end": b[1].isoformat(), "title": b[2]} for b in busy]
        ctx["current_plan"] = self.week_sessions(week_start)
        plan = self.coach.plan_week(ctx, base, instruction)
        self._store_plan(plan)
        return self.week(week_start)

    def _store_plan(self, plan) -> None:
        with self.db.tx() as c:
            c.execute("DELETE FROM plan_sessions WHERE week_start=? AND status='geplant'", (plan.week_start,))
            for s in plan.sessions:
                c.execute(
                    "INSERT INTO plan_sessions(week_start, date, start, end, kind, title, focus, rpe, exercises) "
                    "VALUES (?,?,?,?,?,?,?,?,?)",
                    (plan.week_start, s.date, s.start, s.end, s.kind, s.title, s.focus, s.rpe,
                     json.dumps(s.exercises, ensure_ascii=False)),
                )
            c.execute(
                "INSERT INTO week_notes(week_start, phase, summary, rationale, questions, source, created_at) "
                "VALUES (?,?,?,?,?,?,?) ON CONFLICT(week_start) DO UPDATE SET phase=excluded.phase, "
                "summary=excluded.summary, rationale=excluded.rationale, questions=excluded.questions, "
                "source=excluded.source, created_at=excluded.created_at",
                (plan.week_start, plan.phase, plan.summary, plan.rationale,
                 json.dumps(plan.questions, ensure_ascii=False),
                 "claude" if self.coach.enabled else "regeln", datetime.now().isoformat(timespec="seconds")),
            )

    def week(self, week_start: date) -> dict:
        end = week_start + timedelta(days=6)
        return {
            "week_start": week_start.isoformat(),
            "note": self.week_note(week_start),
            "sessions": self.week_sessions(week_start),
            "activities": self.activities(week_start, end),
            "busy_configured": bool(self.db.get_setting("busy_ics_url")),
        }

    def set_session_status(self, session_id: int, status: str) -> None:
        with self.db.tx() as c:
            c.execute("UPDATE plan_sessions SET status=? WHERE id=?", (status, session_id))

    def all_sessions(self, since: date) -> list[dict]:
        rows = self.db.query("SELECT * FROM plan_sessions WHERE date >= ? ORDER BY date, start", (since.isoformat(),))
        for r in rows:
            r["exercises"] = json.loads(r["exercises"]) if r.get("exercises") else []
        return rows

    # ---------------- Chat ----------------
    def chat_history(self, channel: str, limit: int = 50) -> list[dict]:
        rows = self.db.query("SELECT * FROM chat WHERE channel=? ORDER BY id DESC LIMIT ?", (channel, limit))
        return list(reversed(rows))

    def _chat_add(self, channel: str, role: str, content: str) -> None:
        with self.db.tx() as c:
            c.execute("INSERT INTO chat(channel, ts, role, content) VALUES (?,?,?,?)",
                      (channel, datetime.now().isoformat(timespec="seconds"), role, content))

    def chat(self, message: str) -> dict:
        history = self.chat_history("coach", 20)
        answer = self.coach.chat(history, message, self.context(date.today()))
        self._chat_add("coach", "user", message)
        self._chat_add("coach", "assistant", answer)
        return {"answer": answer, "history": self.chat_history("coach")}

    def week_chat(self, week_start: date, message: str) -> dict:
        channel = f"woche:{week_start.isoformat()}"
        self._chat_add(channel, "user", message)
        if not self.coach.enabled:
            answer = "Planänderungen per Chat brauchen den KI-Coach (ANTHROPIC_API_KEY)."
            self._chat_add(channel, "assistant", answer)
            return {**self.week(week_start), "answer": answer, "history": self.chat_history(channel)}
        result = self.plan_week(week_start, instruction=message)
        note = result.get("note") or {}
        answer = f"Plan angepasst. {note.get('summary', '')}".strip()
        self._chat_add(channel, "assistant", answer)
        return {**result, "answer": answer, "history": self.chat_history(channel)}

    # ---------------- Kontext für den Coach ----------------
    def context(self, d: date, days: int = 14) -> dict[str, Any]:
        start = d - timedelta(days=days - 1)
        metrics = self.metrics_map(start, d)
        journal = self.journal_map(start, d)
        r = self.readiness_for(d)
        settings = self.db.all_settings()
        return {
            "heute": d.isoformat(),
            "wochentag": ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"][d.weekday()],
            "bereitschaft": r.as_dict(),
            "bereitschaft_verlauf": self.readiness_trend(d, min(days, 14)),
            "garmin_tageswerte": [metrics[k] for k in sorted(metrics)],
            "journal": [
                {k: v for k, v in journal[k].items() if k not in ("updated_at",)} for k in sorted(journal)
            ],
            "aktivitaeten": [
                {k: a.get(k) for k in ("date", "kind", "name", "duration_s", "distance_m", "avg_hr", "rpe", "feedback")}
                for a in self.activities(start, d)
            ],
            "plan_diese_woche": self.week_sessions(week_start_of(d)),
            "ziele": settings.get("goals"),
            "vorlieben": settings.get("preferences"),
            "einschraenkungen": settings.get("constraints"),
            "laufziel": settings.get("running_goal"),
            "laufprofil": self.running_profile(d),
            "ernaehrung_ziele": self.nutrition_for(d),
        }


def _minutes(start: str | None, end: str | None) -> float:
    if not start or not end:
        return 0
    s = datetime.strptime(start, "%H:%M")
    e = datetime.strptime(end, "%H:%M")
    return max((e - s).seconds / 60, 0)
