"""Kalender: belegte Zeiten aus einer ICS-Adresse lesen und den Trainingsplan
als ICS-Feed ausgeben (in Google Kalender per "Per URL hinzufügen" abonnierbar)."""

from __future__ import annotations

import re
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import urllib.request


def _unfold(text: str) -> list[str]:
    lines: list[str] = []
    for raw in text.splitlines():
        if raw.startswith((" ", "\t")) and lines:
            lines[-1] += raw[1:]
        else:
            lines.append(raw)
    return lines


def _parse_dt(prop: str, value: str, tz: ZoneInfo) -> datetime | None:
    value = value.strip()
    try:
        if re.fullmatch(r"\d{8}", value):
            return datetime.strptime(value, "%Y%m%d").replace(tzinfo=tz)
        if value.endswith("Z"):
            return datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc).astimezone(tz)
        m = re.search(r"TZID=([^;:]+)", prop)
        src_tz = ZoneInfo(m.group(1)) if m else tz
        return datetime.strptime(value, "%Y%m%dT%H%M%S").replace(tzinfo=src_tz).astimezone(tz)
    except Exception:
        return None


def parse_busy(ics_text: str, start: date, end: date, tz_name: str) -> list[tuple[datetime, datetime, str]]:
    """Gibt belegte Zeiträume zwischen start und end zurück (ohne Wiederholungsregeln)."""
    tz = ZoneInfo(tz_name)
    busy = []
    ev: dict | None = None
    for line in _unfold(ics_text):
        if line == "BEGIN:VEVENT":
            ev = {}
        elif line == "END:VEVENT" and ev is not None:
            s, e = ev.get("start"), ev.get("end")
            if s and not e:
                e = s + timedelta(hours=1)
            if s and e and ev.get("transp") != "TRANSPARENT":
                if s.date() <= end and e.date() >= start:
                    busy.append((s, e, ev.get("summary", "")))
            ev = None
        elif ev is not None and ":" in line:
            prop, value = line.split(":", 1)
            name = prop.split(";", 1)[0].upper()
            if name == "DTSTART":
                ev["start"] = _parse_dt(prop, value, tz)
            elif name == "DTEND":
                ev["end"] = _parse_dt(prop, value, tz)
            elif name == "SUMMARY":
                ev["summary"] = value
            elif name == "TRANSP":
                ev["transp"] = value.strip().upper()
    return busy


def fetch_busy(url: str, start: date, end: date, tz_name: str) -> list[tuple[datetime, datetime, str]]:
    if not url:
        return []
    url = url.replace("webcal://", "https://", 1)
    req = urllib.request.Request(url, headers={"User-Agent": "EchoWP-Trainer"})
    with urllib.request.urlopen(req, timeout=20) as resp:  # noqa: S310 (URL kommt aus deinen Einstellungen)
        text = resp.read().decode("utf-8", errors="replace")
    return parse_busy(text, start, end, tz_name)


def _esc(text: str) -> str:
    return (text or "").replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def build_feed(sessions: list[dict], tz_name: str) -> str:
    tz = ZoneInfo(tz_name)
    now = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//EchoWP//Trainer//DE",
        "CALSCALE:GREGORIAN",
        "X-WR-CALNAME:EchoWP Trainer",
        f"X-WR-TIMEZONE:{tz_name}",
    ]
    for s in sessions:
        start = datetime.fromisoformat(f"{s['date']}T{s.get('start') or '07:00'}").replace(tzinfo=tz)
        end = datetime.fromisoformat(f"{s['date']}T{s.get('end') or '08:00'}").replace(tzinfo=tz)
        lines = [s.get("focus") or ""]
        if s.get("rpe"):
            lines.append(f"Anstrengung: RPE {s['rpe']}/10")
        for ex in s.get("exercises") or []:
            lines.append(f"• {ex.get('name')}: {ex.get('detail', '')}")
        out += [
            "BEGIN:VEVENT",
            f"UID:echowp-trainer-{s['id']}@echowp",
            f"DTSTAMP:{now}",
            f"DTSTART:{start.astimezone(timezone.utc):%Y%m%dT%H%M%SZ}",
            f"DTEND:{end.astimezone(timezone.utc):%Y%m%dT%H%M%SZ}",
            f"SUMMARY:{_esc(s['title'])}",
            f"DESCRIPTION:{_esc(chr(10).join(lines))}",
            "END:VEVENT",
        ]
    out.append("END:VCALENDAR")
    return "\r\n".join(out) + "\r\n"
