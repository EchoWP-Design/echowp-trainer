"""Ausdauerprofil: Zone-2-Pulsbereich, Zone-2-Pace aus den letzten acht Läufen
(falls gelaufen wird) und Kennzahlen der Märsche / des Ruckings."""

from __future__ import annotations

from statistics import mean


def fmt_pace(sec_per_km: float | None) -> str | None:
    if not sec_per_km:
        return None
    m, s = divmod(round(sec_per_km), 60)
    return f"{m}:{s:02d} /km"


def zone2_range(max_hr: float) -> tuple[int, int]:
    return round(max_hr * 0.60), round(max_hr * 0.70)


def profile(runs: list[dict], max_hr: float, walks: list[dict] | None = None) -> dict:
    """runs / walks: Aktivitäten vom Typ 'lauf' bzw. 'gehen', neueste zuerst."""
    lo, hi = zone2_range(max_hr)
    usable = [r for r in runs if r.get("distance_m") and r.get("duration_s") and r["distance_m"] > 1000][:8]
    result = {
        "zone2_hr": [lo, hi],
        "runs_used": len(usable),
        "zone2_pace": None,
        "zone2_pace_s": None,
        "method": None,
        "longest_km": None,
        "marches": march_stats(walks or []),
    }
    if not usable:
        return result
    points = [(r["avg_hr"], r["duration_s"] / (r["distance_m"] / 1000)) for r in usable if r.get("avg_hr")]
    in_z2 = [p for hr, p in points if lo <= hr <= hi]
    pace = None
    if len(in_z2) >= 2:
        pace, method = mean(in_z2), "Durchschnitt der Läufe in Zone 2"
    elif len(points) >= 3 and len({hr for hr, _ in points}) > 1:
        # lineare Regression Pace ~ HF, ausgewertet in der Mitte von Zone 2
        xs, ys = zip(*points)
        mx, my = mean(xs), mean(ys)
        slope = sum((x - mx) * (y - my) for x, y in points) / sum((x - mx) ** 2 for x in xs)
        pace, method = my + slope * ((lo + hi) / 2 - mx), "Hochrechnung aus Puls und Pace"
    if pace:
        result.update(zone2_pace_s=round(pace), zone2_pace=fmt_pace(pace), method=method)
    km = [r["distance_m"] / 1000 for r in usable]
    result["longest_km"] = round(max(km), 1)
    return result


def march_stats(walks: list[dict]) -> dict:
    """Märsche ab 45 Minuten der übergebenen Liste (typisch: letzte 4 Wochen)."""
    marches = [w for w in walks if (w.get("duration_s") or 0) >= 45 * 60]
    km = [(w.get("distance_m") or 0) / 1000 for w in marches]
    pace = None
    with_dist = [w for w in marches if w.get("distance_m")]
    if with_dist:
        pace = sum(w["duration_s"] for w in with_dist) / sum(w["distance_m"] / 1000 for w in with_dist)
    return {
        "count": len(marches),
        "total_km": round(sum(km), 1),
        "longest_km": round(max(km), 1) if km else None,
        "avg_pace": fmt_pace(pace),
    }
