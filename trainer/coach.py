"""KI-Coach mit Claude.

Ohne API-Schlüssel arbeitet die App mit den regelbasierten Texten und Plänen
weiter. Mit Schlüssel formuliert Claude das Tages-Briefing, passt den
Wochenplan an deine Daten an und beantwortet Fragen im Chat.
"""

from __future__ import annotations

import json
import logging
from typing import Any

from .planner import PlannedSession, WeekPlan
from .readiness import Readiness

log = logging.getLogger(__name__)

# Modelle, die den serverseitigen Refusal-Fallback ("default") unterstützen
_FALLBACK_MODELS = {"claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-fable-5-1", "claude-fable-5-2"}

SYSTEM = """Du bist der Performance-Coach in der App "EchoWP Trainer".
Du sprichst Deutsch, duzt, bist direkt, ruhig und konkret. Keine Floskeln, keine Emojis.
Du kennst Trainingslehre (Periodisierung, Zone-2-Training, RPE, Deload, Regeneration)
und begründest Empfehlungen mit den gelieferten Daten (Bereitschafts-Score, Schlaf, HRV,
Ruhepuls, Body Battery, Gefühl, Trainingshistorie, Journal, Ernährung).
Wenn Daten fehlen, sag das kurz, statt etwas zu erfinden.
Trainingsschwerpunkt: Functional Fitness mit Eigengewicht, Kettlebell und Gewichten,
Ausdauer als Steigungsgehen auf dem Laufband, lange Märsche auch mit Rucksack (Rucking).
Wegen Kniebeschwerden: kaum Laufen, keine Sprünge, keine tiefen Ausfallschritte, Kniebeugen
auf Box. Beachte zusätzlich die Einschränkungen im Feld "einschraenkungen".
Bei Warnzeichen (Krankheit, Schmerzen, Brustschmerz, Schwindel) rätst du zu Pause und ärztlicher Abklärung.
Du stellst keine medizinischen Diagnosen."""

WEEK_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "required": ["phase", "summary", "rationale", "questions", "sessions"],
    "properties": {
        "phase": {"type": "string", "enum": ["Aufbau", "Erhaltung", "Deload", "Entlastung"]},
        "summary": {"type": "string"},
        "rationale": {"type": "string"},
        "questions": {"type": "array", "items": {"type": "string"}},
        "sessions": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["date", "start", "end", "kind", "title", "focus", "rpe", "exercises"],
                "properties": {
                    "date": {"type": "string", "description": "YYYY-MM-DD"},
                    "start": {"type": "string", "description": "HH:MM"},
                    "end": {"type": "string", "description": "HH:MM"},
                    "kind": {"type": "string", "enum": ["kraft", "cardio", "intervall", "marsch", "mobility"]},
                    "title": {"type": "string"},
                    "focus": {"type": "string"},
                    "rpe": {"type": "integer"},
                    "exercises": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "detail"],
                            "properties": {"name": {"type": "string"}, "detail": {"type": "string"}},
                        },
                    },
                },
            },
        },
    },
}


class Coach:
    def __init__(self, enabled: bool, model: str):
        self.enabled = enabled
        self.model = model
        self._client = None

    @property
    def client(self):
        if self._client is None:
            import anthropic

            self._client = anthropic.Anthropic()
        return self._client

    def _call(self, messages: list[dict], max_tokens: int = 4000, effort: str = "low",
              schema: dict | None = None) -> str:
        output_config: dict[str, Any] = {"effort": effort}
        if schema:
            output_config["format"] = {"type": "json_schema", "schema": schema}
        kwargs: dict[str, Any] = dict(
            model=self.model,
            max_tokens=max_tokens,
            system=SYSTEM,
            messages=messages,
            output_config=output_config,
        )
        if self.model in _FALLBACK_MODELS:
            kwargs["betas"] = ["server-side-fallback-2026-07-01"]
            kwargs["fallbacks"] = "default"
            resp = self.client.beta.messages.create(**kwargs)
        else:
            resp = self.client.messages.create(**kwargs)
        if resp.stop_reason == "refusal":
            raise RuntimeError("Der Coach hat die Anfrage abgelehnt.")
        if resp.stop_reason == "max_tokens":
            raise RuntimeError("Antwort des Coaches war zu lang und wurde abgeschnitten.")
        return "".join(b.text for b in resp.content if b.type == "text").strip()

    # ------------------------------------------------------------------
    def briefing(self, ctx: dict, readiness: Readiness, today_sessions: list[dict]) -> dict:
        fallback = rule_briefing(readiness, today_sessions)
        if not self.enabled:
            return fallback
        prompt = (
            "Schreib mein Coaching-Briefing für heute in 3 bis 5 kurzen Sätzen. "
            "Sag, ob ich das geplante Training wie geplant, angepasst oder gar nicht machen soll, "
            "und nenn konkrete Anpassungen (RPE, Sätze, Dauer). Danach eine Zeile 'Was heute noch geht:'.\n\n"
            f"Daten:\n{json.dumps(ctx, ensure_ascii=False, default=str)}"
        )
        try:
            text = self._call([{"role": "user", "content": prompt}], max_tokens=2000)
            return {**fallback, "text": text, "source": "claude"}
        except Exception as exc:
            log.warning("Briefing über Claude fehlgeschlagen: %s", exc)
            return fallback

    def plan_week(self, ctx: dict, base: WeekPlan, instruction: str | None = None) -> WeekPlan:
        if not self.enabled:
            return base
        task = (
            "Erstelle meinen Trainingsplan für die Woche ab "
            f"{base.week_start}. Grundlage ist der regelbasierte Entwurf unten. Halte dich an meine "
            "Wochenziele und an die freien Zeitfenster und Termine. Verbessere Reihenfolge, Inhalte und "
            "Intensität anhand meiner Daten der letzten 30 Tage. Übungen mit Sätzen, Wiederholungen und RPE "
            "im Feld detail. Begründe die Phase kurz mit Daten und stelle maximal zwei Rückfragen."
        )
        if instruction:
            task += f"\n\nMeine Änderungswünsche: {instruction}"
        prompt = (
            f"{task}\n\nEntwurf:\n{json.dumps(base.as_dict(), ensure_ascii=False)}\n\n"
            f"Kontext:\n{json.dumps(ctx, ensure_ascii=False, default=str)}"
        )
        try:
            raw = self._call([{"role": "user", "content": prompt}], max_tokens=16000,
                             effort="medium", schema=WEEK_SCHEMA)
            data = json.loads(raw)
            sessions = [
                PlannedSession(
                    date=s["date"], start=s["start"], end=s["end"], kind=s["kind"], title=s["title"],
                    focus=s["focus"], rpe=s.get("rpe"), exercises=s.get("exercises") or [],
                )
                for s in data["sessions"]
                if s["date"][:10] >= base.week_start
            ]
            return WeekPlan(base.week_start, data["phase"], data["summary"], data["rationale"],
                            data["questions"][:2], sorted(sessions, key=lambda s: (s.date, s.start)))
        except Exception as exc:
            log.warning("Wochenplanung über Claude fehlgeschlagen: %s", exc)
            base.rationale += " (KI-Coach nicht erreichbar, regelbasierter Plan.)"
            return base

    def chat(self, history: list[dict], message: str, ctx: dict) -> str:
        if not self.enabled:
            return ("Der KI-Coach ist nicht aktiv. Trag einen ANTHROPIC_API_KEY in der .env ein, "
                    "dann beantworte ich hier Fragen zu Training, Scores und Plan.")
        msgs = [{"role": h["role"], "content": h["content"]} for h in history[-20:]]
        msgs.append({
            "role": "user",
            "content": f"{message}\n\n[Aktuelle Daten]\n{json.dumps(ctx, ensure_ascii=False, default=str)}",
        })
        try:
            return self._call(msgs, max_tokens=3000)
        except Exception as exc:
            log.warning("Chat über Claude fehlgeschlagen: %s", exc)
            return f"Der Coach ist gerade nicht erreichbar ({exc})."


def rule_briefing(r: Readiness, today: list[dict]) -> dict:
    planned = [s for s in today if s.get("kind") != "mobility"]
    title = ", ".join(s["title"] for s in planned) if planned else None
    if r.score is None:
        text = "Noch keine Daten für heute. Synchronisiere Garmin und füll kurz das Journal aus."
    elif r.level == "push":
        text = f"Du bist gut erholt (Score {r.score}). " + (
            f"{title}: wie geplant, gern am oberen Ende der RPE." if title else "Guter Tag für eine harte Einheit."
        )
    elif r.level == "normal":
        text = f"Solide Bereitschaft (Score {r.score}). " + (
            f"{title} wie geplant durchziehen." if title else "Lockeres Training oder Spaziergang passt."
        )
    elif r.level == "locker":
        text = f"Bereitschaft eingeschränkt (Score {r.score}). " + (
            f"{title}: RPE um 1–2 senken und pro Übung einen Satz weniger." if title
            else "Heute nur locker bewegen."
        )
    else:
        text = f"Niedrige Bereitschaft (Score {r.score}). Heute Recovery: Spaziergang, Mobility, früh schlafen."
        if title:
            text += f" {title} verschieben."
    if r.score is not None and r.score >= 50:
        extra = "Was heute noch geht: 20 min Mobility oder ein Spaziergang."
    else:
        extra = "Was heute noch geht: Spaziergang an der frischen Luft, Dehnen."
    return {"text": f"{text}\n{extra}", "source": "regeln", "level": r.level, "label": r.label}
