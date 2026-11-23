from datetime import date

from trainer.calendar_ics import build_feed, parse_busy

ICS = """BEGIN:VCALENDAR
BEGIN:VEVENT
DTSTART;TZID=Europe/Berlin:20261201T180000
DTEND;TZID=Europe/Berlin:20261201T193000
SUMMARY:Zahnarzt
END:VEVENT
BEGIN:VEVENT
DTSTART:20261202T060000Z
DTEND:20261202T070000Z
SUMMARY:Call
TRANSP:TRANSPARENT
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:20270101
SUMMARY:Ausserhalb
END:VEVENT
END:VCALENDAR
"""


def test_parse_busy():
    busy = parse_busy(ICS, date(2026, 11, 30), date(2026, 12, 6), "Europe/Berlin")
    assert len(busy) == 1
    assert busy[0][2] == "Zahnarzt" and busy[0][0].hour == 18


def test_build_feed():
    feed = build_feed([{"id": 7, "date": "2026-12-01", "start": "18:00", "end": "19:00", "title": "Kettlebell, Ganzkörper",
                        "focus": "x", "rpe": 7, "exercises": [{"name": "Swing", "detail": "5 × 15"}]}], "Europe/Berlin")
    assert "DTSTART:20261201T170000Z" in feed
    assert "SUMMARY:Kettlebell\\, Ganzkörper" in feed
    assert feed.count("BEGIN:VEVENT") == 1
