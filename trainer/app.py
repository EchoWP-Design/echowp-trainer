"""FastAPI-Anwendung: REST-API plus die Web-App (PWA) unter /."""

from __future__ import annotations

import hmac
import logging
from datetime import date, timedelta
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import __version__
from .calendar_ics import build_feed
from .config import Settings
from .planner import week_start_of
from .service import TrainerService

STATIC = Path(__file__).parent / "static"
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


class JournalIn(BaseModel):
    mood: int | None = None
    energy: int | None = None
    soreness: int | None = None
    stress: int | None = None
    motivation: int | None = None
    weight_kg: float | None = None
    notes: str | None = None
    food_notes: str | None = None
    food_quality: int | None = None
    corrections: dict | None = None
    briefing_read: bool | None = None


class FeedbackIn(BaseModel):
    rpe: int | None = None
    feedback: str | None = None


class ChatIn(BaseModel):
    message: str


class StatusIn(BaseModel):
    status: str


def _parse_date(value: str | None) -> date:
    if not value:
        return date.today()
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise HTTPException(400, "Datum im Format JJJJ-MM-TT angeben") from exc


def create_app(settings: Settings | None = None, service: TrainerService | None = None) -> FastAPI:
    settings = settings or Settings.load()
    svc = service or TrainerService(settings)
    app = FastAPI(title="EchoWP Trainer", version=__version__)
    app.state.service = svc
    _start_autosync(svc)

    @app.middleware("http")
    async def auth(request: Request, call_next):
        token = settings.app_token
        path = request.url.path
        if token and (path.startswith("/api/") or path == "/calendar.ics"):
            given = request.headers.get("authorization", "").removeprefix("Bearer ").strip()
            given = given or request.query_params.get("token", "")
            if not hmac.compare_digest(given, token):
                return JSONResponse({"detail": "Nicht angemeldet"}, status_code=401)
        return await call_next(request)

    # ---------------- API ----------------
    @app.get("/api/health")
    def health():
        return {"ok": True, "version": __version__, "coach": svc.coach.enabled,
                "source": getattr(svc.source, "name", None), "auth": bool(settings.app_token)}

    @app.get("/api/dashboard")
    def dashboard(day: str | None = None):
        return svc.dashboard(_parse_date(day))

    @app.post("/api/sync")
    def sync(days: int = 3):
        result = svc.sync(days=max(1, min(days, 60)), activity_days=max(14, min(days, 60)))
        return result

    @app.post("/api/import")
    async def import_files(files: list[UploadFile] = File(...)):
        payload = [(f.filename or "datei", await f.read()) for f in files]
        return svc.import_files(payload)

    @app.post("/api/briefing")
    def briefing(day: str | None = None):
        return svc.refresh_briefing(_parse_date(day))

    @app.get("/api/journal/{day}")
    def journal_get(day: str):
        d = _parse_date(day).isoformat()
        return {
            "journal": svc.journal_entry(d),
            "metrics": svc.db.one("SELECT * FROM daily_metrics WHERE date=?", (d,)),
            "activities": svc.activities(_parse_date(day), _parse_date(day)),
            "readiness": svc.readiness_for(_parse_date(day)).as_dict(),
        }

    @app.put("/api/journal/{day}")
    def journal_put(day: str, body: JournalIn):
        d = _parse_date(day).isoformat()
        return svc.save_journal(d, body.model_dump(exclude_none=True))

    @app.put("/api/activities/{activity_id}/feedback")
    def feedback(activity_id: str, body: FeedbackIn):
        svc.activity_feedback(activity_id, body.rpe, body.feedback)
        return {"ok": True}

    @app.get("/api/week")
    def week(start: str | None = None):
        return svc.week(week_start_of(_parse_date(start)))

    @app.post("/api/week/plan")
    def plan(start: str | None = None):
        return svc.plan_week(week_start_of(_parse_date(start)))

    @app.post("/api/week/chat")
    def week_chat(body: ChatIn, start: str | None = None):
        return svc.week_chat(week_start_of(_parse_date(start)), body.message)

    @app.get("/api/week/chat")
    def week_chat_history(start: str | None = None):
        return {"history": svc.chat_history(f"woche:{week_start_of(_parse_date(start)).isoformat()}")}

    @app.put("/api/sessions/{session_id}/status")
    def session_status(session_id: int, body: StatusIn):
        if body.status not in ("geplant", "erledigt", "ausgelassen"):
            raise HTTPException(400, "Status muss geplant, erledigt oder ausgelassen sein")
        svc.set_session_status(session_id, body.status)
        return {"ok": True}

    @app.get("/api/chat")
    def chat_history():
        return {"history": svc.chat_history("coach")}

    @app.post("/api/chat")
    def chat(body: ChatIn):
        if not body.message.strip():
            raise HTTPException(400, "Nachricht ist leer")
        return svc.chat(body.message.strip())

    @app.get("/api/nutrition")
    def nutrition_get(day: str | None = None):
        return {"targets": svc.nutrition_for(_parse_date(day)), "profile": svc.db.get_setting("profile")}

    @app.get("/api/settings")
    def settings_get():
        s = svc.db.all_settings()
        return {k: v for k, v in s.items() if not k.startswith("briefing:")}

    @app.put("/api/settings")
    def settings_put(body: dict):
        allowed = {"goals", "max_hr", "sleep_target_h", "slots", "busy_ics_url", "preferences",
                   "running_goal", "profile", "constraints"}
        for k, v in body.items():
            if k in allowed:
                svc.db.set_setting(k, v)
        return settings_get()

    @app.get("/calendar.ics")
    def calendar():
        sessions = svc.all_sessions(date.today() - timedelta(days=14))
        return Response(build_feed(sessions, settings.timezone), media_type="text/calendar; charset=utf-8")

    # ---------------- Web-App ----------------
    app.mount("/static", StaticFiles(directory=STATIC), name="static")

    @app.get("/manifest.webmanifest")
    def manifest():
        return FileResponse(STATIC / "manifest.webmanifest", media_type="application/manifest+json")

    @app.get("/sw.js")
    def sw():
        return FileResponse(STATIC / "sw.js", media_type="application/javascript")

    @app.get("/")
    def index():
        return FileResponse(STATIC / "index.html")

    return app


def _start_autosync(svc: TrainerService) -> None:
    """Holt alle TRAINER_AUTOSYNC_HOURS Stunden neue Garmin-Daten (0 = aus)."""
    import os
    import threading
    import time

    hours = float(os.environ.get("TRAINER_AUTOSYNC_HOURS", "3") or 0)
    if hours <= 0 or svc.source is None or os.environ.get("PYTEST_CURRENT_TEST"):
        return

    def loop():
        while True:
            time.sleep(hours * 3600)
            try:
                svc.sync(days=2, activity_days=3)
            except Exception:  # pragma: no cover
                logging.getLogger(__name__).exception("Auto-Sync fehlgeschlagen")

    threading.Thread(target=loop, name="garmin-autosync", daemon=True).start()


def main() -> None:  # pragma: no cover
    import os

    import uvicorn

    uvicorn.run(create_app(), host=os.environ.get("HOST", "0.0.0.0"), port=int(os.environ.get("PORT", "8080")))


if __name__ == "__main__":  # pragma: no cover
    main()
