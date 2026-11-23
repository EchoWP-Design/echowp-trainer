from datetime import date, timedelta

from fastapi.testclient import TestClient

from trainer.app import create_app
from trainer.planner import week_start_of


def test_full_flow(settings, service):
    client = TestClient(create_app(settings, service))
    assert client.get("/api/health").json()["ok"]
    r = client.post("/api/sync?days=21").json()
    assert r["ok"], r

    today = date.today().isoformat()
    client.put(f"/api/journal/{today}", json={"mood": 7, "energy": 6, "soreness": 3, "stress": 4,
                                              "motivation": 8, "weight_kg": 82.5, "food_notes": "Haferflocken"})
    d = client.get(f"/api/dashboard?day={today}").json()
    assert d["readiness"]["score"] is not None
    assert d["nutrition"]["weight_kg"] == 82.5
    assert any(x["key"] == "weight" and x["done"] for x in d["ritual"])
    assert len(d["streaks"]["habits"][0]["days"]) == 28

    nxt = (week_start_of(date.today()) + timedelta(days=7)).isoformat()
    w = client.post(f"/api/week/plan?start={nxt}").json()
    assert w["note"]["phase"] and len(w["sessions"]) >= 8
    sid = w["sessions"][0]["id"]
    assert client.put(f"/api/sessions/{sid}/status", json={"status": "erledigt"}).json()["ok"]

    ics = client.get("/calendar.ics")
    assert ics.status_code == 200 and "BEGIN:VEVENT" in ics.text

    chat = client.post("/api/chat", json={"message": "Wie geht's?"}).json()
    assert "ANTHROPIC_API_KEY" in chat["answer"]
    assert client.get("/").status_code == 200


def test_token_protection(settings, service):
    from dataclasses import replace

    s = replace(settings, app_token="geheim")
    client = TestClient(create_app(s, service))
    assert client.get("/api/dashboard").status_code == 401
    assert client.get("/api/health", headers={"Authorization": "Bearer geheim"}).status_code == 200
    assert client.get("/calendar.ics?token=geheim").status_code == 200
    assert client.get("/").status_code == 200  # App-Hülle ist öffentlich, Daten nicht
