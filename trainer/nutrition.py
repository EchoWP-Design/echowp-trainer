"""Kalorien- und Makrorechner mit zwei Modi.

1. ``jan``: Jans Excel-Rechner (Rechner_Kalorien.xlsx), 1:1 übernommen:

       Kalorien (kcal)      = Gewicht * 26
       Protein (g)          = Gewicht * 2
       Fett (g)             = Kalorien / 30            (= 30 % der Energie)
       Ballaststoffe (g)    = Kalorien * 0,014         (= 14 g / 1000 kcal)
       Kohlenhydrate (g)    = (Kalorien - Protein*4 - Fett*9) / 4
       Wasser (l)           = Gewicht / 30

2. ``wissenschaft`` (Standard): gleiche Makro-Logik, aber der Energiebedarf
   wird individuell berechnet:

   * Grundumsatz nach Mifflin-St Jeor (1990), der in Reviews genauesten
     Schätzformel für gesunde Erwachsene ohne Körperfettmessung:
     Männer 10·kg + 6,25·cm − 5·Alter + 5, Frauen … − 161.
   * Gesamtumsatz = Grundumsatz × PAL. Der PAL ergibt sich aus den
     Trainingsstunden pro Woche (Garmin) nach den DGE-Stufen 1,4 … 2,0.
   * Ziel: Abnehmen −15 %, Halten ±0, Aufbauen +10 %.
   * Protein 2,0 g/kg (Halten/Aufbauen), 2,2 g/kg im Defizit (ISSN 2017).
   * Fett 30 % der Energie, mindestens 0,8 g/kg (DGE, Hormonhaushalt).
   * Ballaststoffe 14 g / 1000 kcal, mindestens 30 g (DGE).
   * Kohlenhydrate = Rest; Warnung unter 3 g/kg bei ≥ 3 h Ausdauer/Woche
     (ACSM/IOC 2016: 3–7 g/kg je nach Umfang).
   * Wasser 35 ml/kg + 0,75 l je Trainingsstunde des Tages (EFSA / ACSM).
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import date

MODES = ("wissenschaft", "jan")
GOALS = {"abnehmen": -0.15, "halten": 0.0, "aufbauen": 0.10}

# DGE-PAL-Stufen nach Trainingsstunden pro Woche
PAL_STEPS = [(1, 1.4), (3, 1.55), (5, 1.7), (8, 1.85)]
PAL_MAX = 2.0


@dataclass
class NutritionTargets:
    mode: str
    weight_kg: float
    kcal: float
    protein_g: float
    fat_g: float
    fiber_g: float
    carbs_g: float
    water_l: float
    protein_pct: float
    fat_pct: float
    carbs_pct: float
    carbs_g_per_kg: float
    bmr: float | None = None
    pal: float | None = None
    goal: str | None = None
    hints: list[str] = field(default_factory=list)

    def as_dict(self) -> dict:
        return asdict(self)


def _finish(mode, weight, kcal, protein, fat, fiber, water, **extra) -> NutritionTargets:
    kcal_after_protein = kcal - protein * 4  # Excel C10
    kcal_for_carbs = kcal_after_protein - fat * 9  # Excel D10
    carbs = max(kcal_for_carbs / 4, 0)
    return NutritionTargets(
        mode=mode,
        weight_kg=round(weight, 1),
        kcal=round(kcal),
        protein_g=round(protein),
        fat_g=round(fat),
        fiber_g=round(fiber),
        carbs_g=round(carbs),
        water_l=round(water, 1),
        protein_pct=round(protein * 4 / kcal * 100),
        fat_pct=round(fat * 9 / kcal * 100),
        carbs_pct=round(carbs * 4 / kcal * 100),
        carbs_g_per_kg=round(carbs / weight, 1),
        **extra,
    )


def calculate_jan(weight_kg: float) -> NutritionTargets:
    """Jans Excel-Formeln, unverändert."""
    _check_weight(weight_kg)
    kcal = weight_kg * 26
    return _finish(
        "jan",
        weight_kg,
        kcal=kcal,
        protein=weight_kg * 2,
        fat=kcal / 30,
        fiber=kcal * 0.014,
        water=weight_kg / 30,
    )


def mifflin_st_jeor(weight_kg: float, height_cm: float, age: int, sex: str) -> float:
    base = 10 * weight_kg + 6.25 * height_cm - 5 * age
    return base + (5 if sex == "m" else -161)


def pal_from_training(hours_per_week: float) -> float:
    for limit, pal in PAL_STEPS:
        if hours_per_week < limit:
            return pal
    return PAL_MAX


def calculate_science(
    weight_kg: float,
    height_cm: float,
    age: int,
    sex: str,
    training_h_week: float,
    goal: str = "halten",
    endurance_h_week: float = 0.0,
    training_h_today: float = 0.0,
) -> NutritionTargets:
    _check_weight(weight_kg)
    if goal not in GOALS:
        goal = "halten"
    bmr = mifflin_st_jeor(weight_kg, height_cm, age, sex)
    pal = pal_from_training(training_h_week)
    kcal = bmr * pal * (1 + GOALS[goal])
    protein = weight_kg * (2.2 if goal == "abnehmen" else 2.0)
    fat = max(kcal * 0.30 / 9, weight_kg * 0.8)
    fiber = max(kcal / 1000 * 14, 30)
    water = weight_kg * 0.035 + training_h_today * 0.75
    t = _finish(
        "wissenschaft",
        weight_kg,
        kcal=kcal,
        protein=protein,
        fat=fat,
        fiber=fiber,
        water=water,
        bmr=round(bmr),
        pal=pal,
        goal=goal,
    )
    if endurance_h_week >= 3 and t.carbs_g_per_kg < 3:
        t.hints.append(
            "Kohlenhydrate unter 3 g/kg bei viel Ausdauertraining: "
            "Regeneration und Leistung können leiden."
        )
    if goal == "abnehmen":
        t.hints.append("Defizit von 15 %: Gewichtsverlauf wöchentlich prüfen, Ziel 0,5–1 % pro Woche.")
    return t


def calculate(weight_kg: float, profile: dict | None = None, training: dict | None = None) -> NutritionTargets:
    """Wählt den Modus aus dem Profil. Fehlen Größe/Alter/Geschlecht, fällt
    die Berechnung auf Jans Formel zurück und sagt das im Hinweis."""
    profile = profile or {}
    training = training or {}
    mode = profile.get("nutrition_mode", "wissenschaft")
    if mode == "jan":
        return calculate_jan(weight_kg)
    height, birth_year, sex = profile.get("height_cm"), profile.get("birth_year"), profile.get("sex")
    if not (height and birth_year and sex in ("m", "w")):
        t = calculate_jan(weight_kg)
        t.hints.append("Größe, Geburtsjahr und Geschlecht in den Einstellungen eintragen, dann rechne ich genauer.")
        return t
    age = date.today().year - int(birth_year)
    return calculate_science(
        weight_kg,
        float(height),
        age,
        sex,
        training_h_week=training.get("hours_week", 0.0),
        goal=profile.get("goal", "halten"),
        endurance_h_week=training.get("endurance_hours_week", 0.0),
        training_h_today=training.get("hours_today", 0.0),
    )


def _check_weight(weight_kg: float) -> None:
    if weight_kg is None or weight_kg <= 0:
        raise ValueError("Körpergewicht muss größer als 0 sein")
