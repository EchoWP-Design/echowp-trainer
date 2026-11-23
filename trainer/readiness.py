"""Bereitschafts-Score 0–100 aus Garmin-Daten und Gefühl.

Der Score kombiniert objektive Werte mit deiner eigenen Einschätzung, weil
Garmins Body Battery dich an manchen Tagen auf 100 sieht, obwohl du dich wie
0 fühlst. Deshalb zählt das Gefühl am stärksten und kann den Score deckeln.

Komponenten (je 0–100) und Gewichte:
  Schlaf        25 %  Dauer gegenüber Ziel, gemischt mit Garmin-Schlafscore
  HRV           20 %  letzte Nacht gegenüber eigenem 7-Tage-Schnitt
  Ruhepuls      10 %  Abweichung vom eigenen 7-Tage-Schnitt
  Body Battery  15 %  Wert am Morgen
  Gefühl        30 %  Stimmung, Energie, Muskelkater, Stress, Motivation
Fehlende Komponenten werden herausgerechnet, die übrigen neu gewichtet.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from statistics import mean

WEIGHTS = {"sleep": 0.25, "hrv": 0.20, "rhr": 0.10, "body_battery": 0.15, "subjective": 0.30}


def _clamp(v: float, lo: float = 0, hi: float = 100) -> float:
    return max(lo, min(hi, v))


def _lin(x: float, x0: float, y0: float, x1: float, y1: float) -> float:
    if x1 == x0:
        return y1
    return _clamp(y0 + (x - x0) * (y1 - y0) / (x1 - x0))


@dataclass
class Readiness:
    score: int | None
    level: str  # "push" | "normal" | "locker" | "recovery" | "unbekannt"
    label: str
    components: dict
    notes: list

    def as_dict(self) -> dict:
        return asdict(self)


def sleep_component(hours: float | None, score: float | None, target: float) -> float | None:
    parts = []
    if hours is not None:
        parts.append(_lin(hours, target - 4, 0, target, 100))
    if score is not None:
        parts.append(_clamp(score))
    return mean(parts) if parts else None


def hrv_component(today: float | None, baseline: list[float]) -> float | None:
    if today is None or len(baseline) < 3:
        return None
    ratio = today / mean(baseline)
    # 100 ab Baseline, 40 bei 80 %, 0 bei 65 %
    if ratio >= 1:
        return 100.0
    if ratio >= 0.8:
        return _lin(ratio, 0.8, 40, 1.0, 100)
    return _lin(ratio, 0.65, 0, 0.8, 40)


def rhr_component(today: float | None, baseline: list[float]) -> float | None:
    if today is None or len(baseline) < 3:
        return None
    delta = today - mean(baseline)
    return _lin(delta, 0, 100, 8, 20) if delta > 0 else 100.0


def subjective_component(j: dict | None) -> float | None:
    if not j:
        return None
    vals = []
    for key, inverted in (("mood", False), ("energy", False), ("motivation", False),
                          ("soreness", True), ("stress", True)):
        v = j.get(key)
        if v is None:
            continue
        v = _clamp(float(v), 1, 10)
        vals.append((10 - v) / 9 * 100 if inverted else (v - 1) / 9 * 100)
    return mean(vals) if vals else None


def compute(
    metrics: dict | None,
    journal: dict | None,
    history: list[dict],
    sleep_target: float = 8.0,
) -> Readiness:
    """metrics/journal: Werte des Tages; history: daily_metrics der Vortage (neueste zuerst)."""
    m = dict(metrics or {})
    # Korrekturen aus dem Journal überschreiben Garmin-Werte
    corrections = (journal or {}).get("corrections") or {}
    m.update({k: v for k, v in corrections.items() if v is not None})

    hrv_base = [h["hrv_ms"] for h in history[:7] if h.get("hrv_ms")]
    rhr_base = [h["resting_hr"] for h in history[:7] if h.get("resting_hr")]
    comps = {
        "sleep": sleep_component(m.get("sleep_hours"), m.get("sleep_score"), sleep_target),
        "hrv": hrv_component(m.get("hrv_ms"), hrv_base),
        "rhr": rhr_component(m.get("resting_hr"), rhr_base),
        "body_battery": _clamp(m["body_battery"]) if m.get("body_battery") is not None else None,
        "subjective": subjective_component(journal),
    }
    present = {k: v for k, v in comps.items() if v is not None}
    notes: list[str] = []
    if not present:
        return Readiness(None, "unbekannt", "Keine Daten", comps, ["Garmin synchronisieren oder Journal ausfüllen."])

    total_w = sum(WEIGHTS[k] for k in present)
    score = sum(present[k] * WEIGHTS[k] for k in present) / total_w

    subj = comps["subjective"]
    if subj is not None and subj < 40 and score > subj + 15:
        score = subj + 15
        notes.append("Dein Gefühl ist deutlich schlechter als die Messwerte. Ich gehe nach dem Gefühl.")
    if subj is None:
        notes.append("Ohne Gefühlsfeedback ist der Score ungenauer. Kurz das Journal ausfüllen.")
    if comps["hrv"] is not None and comps["hrv"] < 40:
        notes.append("HRV klar unter deinem Schnitt: Zeichen für Belastung oder beginnenden Infekt.")
    if comps["rhr"] is not None and comps["rhr"] < 50:
        notes.append("Ruhepuls erhöht gegenüber deinem Schnitt.")

    s = round(score)
    if s >= 80:
        level, label = "push", "Push Day"
    elif s >= 65:
        level, label = "normal", "Training wie geplant"
    elif s >= 50:
        level, label = "locker", "Intensität reduzieren"
    else:
        level, label = "recovery", "Recovery / Mobility"
    rounded = {k: (round(v) if v is not None else None) for k, v in comps.items()}
    return Readiness(s, level, label, rounded, notes)
