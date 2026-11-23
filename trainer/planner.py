"""Regelbasierte Wochenplanung.

Funktioniert ohne KI und ist die Grundlage, auf der der KI-Coach aufsetzt.
Ablauf:
  1. Phase bestimmen: Aufbauwoche, Erhaltung oder Entlastung (Deload), aus der
     mittleren Bereitschaft der letzten 7 Tage und dem 4-Wochen-Zyklus.
  2. Freie Zeitfenster je Tag aus den Einstellungen nehmen, belegte Termine
     aus dem Kalender abziehen.
  3. Langer Marsch (Rucking) aufs Wochenende, dann Functional-Kraft, dann
     Steigungsgehen auf dem Laufband, dann Mobility. Wegen Kniebeschwerden
     kein Laufen und keine Sprünge im Standardplan.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timedelta

# Schwerpunkt: Functional Fitness mit Eigengewicht, Kettlebell und Gewichten.
# Knieschonend: keine Sprünge, keine tiefen Ausfallschritte, Kniebeugen auf Box.
STRENGTH_SPLITS = {
    5: ["Kettlebell Ganzkörper", "Functional Push", "Functional Pull", "Hüfte & Rumpf", "Carry & Conditioning"],
    4: ["Kettlebell Ganzkörper", "Functional Push", "Functional Pull", "Hüfte & Rumpf"],
    3: ["Kettlebell Ganzkörper", "Functional Push/Pull", "Hüfte & Rumpf"],
    2: ["Kettlebell Ganzkörper", "Functional Push/Pull"],
    1: ["Kettlebell Ganzkörper"],
}

EXERCISES = {
    "Kettlebell Ganzkörper": [
        ("Kettlebell Swing", 5, "15"), ("Goblet Box Squat", 4, "10"), ("Kettlebell Clean & Press", 4, "6/Seite"),
        ("Turkish Get-up", 3, "2/Seite"), ("Kettlebell Row", 3, "10/Seite"), ("Dead Bug", 3, "10/Seite"),
    ],
    "Functional Push": [
        ("Liegestütz (ggf. erhöht)", 4, "10–15"), ("Kettlebell Floor Press", 4, "8/Seite"),
        ("Landmine Press", 3, "8/Seite"), ("Dips an Barren/Bank", 3, "8–12"),
        ("Plank Shoulder Taps", 3, "20"), ("Farmer's Carry", 3, "40 m"),
    ],
    "Functional Pull": [
        ("Klimmzüge / Negativ", 4, "5–8"), ("Inverted Row (Ringe/TRX)", 4, "10"),
        ("Kettlebell Gorilla Row", 3, "8/Seite"), ("Face Pulls Band", 3, "15"),
        ("Hanging Knee Raise", 3, "10"), ("Suitcase Carry", 3, "30 m/Seite"),
    ],
    "Functional Push/Pull": [
        ("Liegestütz", 4, "10–15"), ("Inverted Row", 4, "10"), ("Kettlebell Clean & Press", 3, "6/Seite"),
        ("Klimmzüge / Negativ", 3, "5–8"), ("Farmer's Carry", 3, "40 m"),
    ],
    "Hüfte & Rumpf": [
        ("Kreuzheben (Kettlebell/Trap Bar)", 4, "6–8"), ("Hip Thrust", 4, "10"),
        ("Step-up niedrige Box", 3, "8/Seite"), ("Single-Leg RDL Kettlebell", 3, "8/Seite"),
        ("Copenhagen Plank (kurz)", 3, "20 s/Seite"), ("Pallof Press", 3, "10/Seite"),
    ],
    "Carry & Conditioning": [
        ("Zirkel 4 Runden: Kettlebell Swing", 4, "15"), ("Burpee ohne Sprung", 4, "8"),
        ("Bear Crawl", 4, "15 m"), ("Sandbag/KB Front Carry", 4, "40 m"),
        ("Mountain Climber langsam", 4, "20"),
    ],
}

MOBILITY = [("Hüftöffner 90/90", 2, "60 s/Seite"), ("Thorax-Rotation", 2, "10/Seite"),
            ("Couch Stretch (Knie gepolstert)", 2, "60 s/Seite"), ("Cat-Cow", 2, "10"),
            ("Terminal Knee Extension mit Band", 2, "15/Seite"), ("Faszienrolle Waden/Oberschenkel", 1, "5 min")]

DURATION_MIN = {"kraft": 60, "cardio": 45, "intervall": 40, "marsch": 100, "mobility": 25}

@dataclass
class PlannedSession:
    date: str
    start: str
    end: str
    kind: str  # kraft | cardio | intervall | marsch | mobility
    title: str
    focus: str
    rpe: int | None
    exercises: list[dict] = field(default_factory=list)

    def as_dict(self) -> dict:
        return asdict(self)


@dataclass
class WeekPlan:
    week_start: str
    phase: str
    summary: str
    rationale: str
    questions: list[str]
    sessions: list[PlannedSession]
    unplaced: list[str] = field(default_factory=list)

    def as_dict(self) -> dict:
        d = asdict(self)
        return d


def week_start_of(d: date) -> date:
    return d - timedelta(days=d.weekday())


def determine_phase(week_start: date, avg_readiness: float | None) -> tuple[str, float, int]:
    """Gibt (Phase, Volumenfaktor, RPE-Korrektur) zurück."""
    cycle_week = week_start.isocalendar().week % 4
    if avg_readiness is not None and avg_readiness < 55:
        return "Entlastung", 0.7, -2
    if cycle_week == 0:
        return "Deload", 0.7, -1
    if avg_readiness is not None and avg_readiness < 65:
        return "Erhaltung", 0.9, -1
    return "Aufbau", 1.0 + 0.05 * (cycle_week - 1), 0


def _free_windows(day: date, slots: dict, busy: list[tuple[datetime, datetime, str]]) -> list[tuple[str, str]]:
    windows = []
    for start_s, end_s in slots.get(str(day.weekday()), []):
        start = datetime.fromisoformat(f"{day}T{start_s}")
        end = datetime.fromisoformat(f"{day}T{end_s}")
        blocked = False
        for b_start, b_end, title in busy:
            bs, be = b_start.replace(tzinfo=None), b_end.replace(tzinfo=None)
            # Eigene Trainingsblocker im Kalender dürfen überschrieben werden
            if "training" in (title or "").lower():
                continue
            if bs < end and be > start:
                blocked = True
                break
        if not blocked:
            windows.append((start_s, end_s))
    return windows


def _fit(window: tuple[str, str], minutes: int, day: date) -> tuple[str, str]:
    start = datetime.fromisoformat(f"{day}T{window[0]}")
    end = datetime.fromisoformat(f"{day}T{window[1]}")
    stop = min(end, start + timedelta(minutes=minutes))
    return start.strftime("%H:%M"), stop.strftime("%H:%M")


def _strength_exercises(split: str, volume: float, rpe_adj: int) -> list[dict]:
    base = EXERCISES.get(split, EXERCISES["Kettlebell Ganzkörper"])
    out = []
    for i, (name, sets, reps) in enumerate(base):
        s = max(2, round(sets * volume))
        rpe = (8 if i < 2 else 7) + rpe_adj
        if split == "Carry & Conditioning":
            rpe = 7 + rpe_adj
        out.append({"name": name, "sets": s, "reps": reps, "detail": f"{s} × {reps} @ RPE {rpe}"})
    return out


def build_week(
    week_start: date,
    settings: dict,
    avg_readiness: float | None = None,
    busy: list | None = None,
    zone2_hr: tuple[int, int] | list | None = None,
) -> WeekPlan:
    goals = settings.get("goals", {})
    slots = settings.get("slots", {})
    busy = busy or []
    phase, volume, rpe_adj = determine_phase(week_start, avg_readiness)
    days = [week_start + timedelta(days=i) for i in range(7)]
    free = {d: _free_windows(d, slots, busy) for d in days}
    used: dict[date, int] = {d: 0 for d in days}  # Anzahl Einheiten pro Tag
    sessions: list[PlannedSession] = []
    unplaced: list[str] = []

    def take(day: date, minutes: int, prefer: str = "any") -> tuple[str, str] | None:
        wins = free[day]
        if not wins or used[day] >= 2:
            return None
        idx = 0 if prefer == "am" else (len(wins) - 1 if prefer == "pm" else 0)
        win = wins.pop(idx)
        used[day] += 1
        return _fit(win, minutes, day)

    z2 = f"Zone 2 ({zone2_hr[0]}–{zone2_hr[1]} bpm)" if zone2_hr else "Zone 2 (locker, Sprechen möglich)"

    # 1. Langer Marsch / Rucking (Sonntag, sonst Samstag)
    long_days: list[date] = []
    n_march = goals.get("march", goals.get("longrun", 0))
    for _ in range(n_march):
        for d in (days[6], days[5]):
            if d in long_days:
                continue
            t = take(d, DURATION_MIN["marsch"], "am")
            if t:
                long_days.append(d)
                minutes = round(80 * volume)
                load = "8–10 kg" if phase in ("Deload", "Entlastung") else "10–15 kg"
                sessions.append(PlannedSession(
                    d.isoformat(), *t, "marsch", "Langer Marsch (Rucking)",
                    f"{minutes} min zügig gehen mit Rucksack {load}, {z2}. Hügel erlaubt, "
                    "bergab kurze Schritte (knieschonend).", 5 + rpe_adj,
                ))
                break
        else:
            unplaced.append("Langer Marsch")

    # 2. Krafteinheiten, möglichst verteilt (abends)
    n_strength = goals.get("strength", 0)
    split = STRENGTH_SPLITS.get(min(n_strength, 5), STRENGTH_SPLITS[5])
    strength_order = [0, 1, 2, 3, 4, 5, 6]
    placed = 0
    for i in strength_order:
        if placed >= n_strength:
            break
        d = days[i]
        if d in long_days:
            continue
        t = take(d, DURATION_MIN["kraft"], "pm")
        if t:
            name = split[placed % len(split)]
            sessions.append(PlannedSession(
                d.isoformat(), *t, "kraft", f"{name} Day" if name in ("Push", "Pull") else name,
                "Schwere Grundübungen zuerst, danach leichter werden.", 7 + rpe_adj,
                _strength_exercises(name, volume, rpe_adj),
            ))
            placed += 1
    unplaced += ["Kraft"] * (n_strength - placed)

    # 3. Ausdauer auf dem Laufband mit Steigung (knieschonend statt Laufen),
    #    Steigungsintervalle nur in Aufbauwochen
    n_cardio = goals.get("cardio", 0)
    cardio_order = [1, 3, 5, 0, 2, 4, 6]
    c_placed = 0
    for i in cardio_order:
        if c_placed >= n_cardio:
            break
        d = days[i]
        if d in long_days:
            continue
        next_is_long = (d + timedelta(days=1)) in long_days
        interval = phase == "Aufbau" and c_placed == 1 and not next_is_long
        kind = "intervall" if interval else "cardio"
        t = take(d, DURATION_MIN[kind], "am")
        if not t:
            continue
        if interval:
            sessions.append(PlannedSession(
                d.isoformat(), *t, "intervall", "Steigungsintervalle Laufband",
                "8 min einlaufen (5 km/h, 3 %), dann 6 × 3 min zügig gehen bei 12–15 % Steigung "
                "und 2 min locker bei 3 %, 5 min auslaufen. Nicht am Geländer festhalten.", 7 + rpe_adj,
            ))
        else:
            minutes = round(40 * volume)
            sessions.append(PlannedSession(
                d.isoformat(), *t, "cardio", "Steigungsgehen Laufband",
                f"{minutes} min bei 8–12 % Steigung, 5–6 km/h, {z2}.", 4,
            ))
        c_placed += 1
    unplaced += ["Ausdauer"] * (n_cardio - c_placed)

    # 4. Mobility am Tag nach dem langen Lauf bzw. an einem freien Abend
    for d in [x + timedelta(days=1) for x in long_days if x + timedelta(days=1) in free] + days:
        t = take(d, DURATION_MIN["mobility"], "pm")
        if t:
            sessions.append(PlannedSession(
                d.isoformat(), *t, "mobility", "Mobility", "Ruhig, Fokus Hüfte und Brustwirbelsäule.", 2,
                [{"name": n, "sets": s, "reps": r, "detail": f"{s} × {r}"} for n, s, r in MOBILITY],
            ))
            break

    sessions.sort(key=lambda s: (s.date, s.start))
    summary = {
        "Aufbau": "Aufbauwoche: Umfang leicht erhöht.",
        "Erhaltung": "Erhaltungswoche: Umfang halten, Intensität etwas runter.",
        "Deload": "Deload-Woche: weniger Sätze, mehr Erholung. Danach geht's wieder hoch.",
        "Entlastung": "Entlastungswoche: deine Bereitschaft war niedrig, wir nehmen Druck raus.",
    }[phase]
    rationale = (
        f"Mittlere Bereitschaft der letzten 7 Tage: "
        f"{round(avg_readiness) if avg_readiness is not None else 'unbekannt'}. "
        f"Woche {week_start.isocalendar().week % 4 or 4} im 4-Wochen-Zyklus."
    )
    if unplaced:
        rationale += f" Nicht untergebracht (keine freien Fenster): {', '.join(unplaced)}."
    questions = ["Passen die Zeiten zu deinen Terminen?"]
    if phase in ("Entlastung", "Erhaltung"):
        questions.append("Gibt es einen Grund für die niedrige Bereitschaft (Stress, Krankheit, Knie)?")
    return WeekPlan(week_start.isoformat(), phase, summary, rationale, questions, sessions, unplaced)
