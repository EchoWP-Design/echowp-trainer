from trainer.readiness import compute

HIST = [{"hrv_ms": 60, "resting_hr": 50}] * 7


def test_good_day_is_push():
    r = compute({"sleep_hours": 8.2, "sleep_score": 90, "hrv_ms": 64, "resting_hr": 49, "body_battery": 95},
                {"mood": 9, "energy": 9, "motivation": 9, "soreness": 2, "stress": 2}, HIST)
    assert r.score >= 80 and r.level == "push"


def test_feeling_caps_score():
    # Garmin sagt topfit, Gefühl sagt nein -> Gefühl gewinnt
    r = compute({"sleep_hours": 8.5, "sleep_score": 95, "hrv_ms": 70, "resting_hr": 48, "body_battery": 100},
                {"mood": 2, "energy": 1, "motivation": 2, "soreness": 9, "stress": 9}, HIST)
    assert r.score <= r.components["subjective"] + 15
    assert r.level == "recovery"


def test_missing_components_reweighted():
    r = compute({"body_battery": 70}, None, [])
    assert r.score == 70


def test_corrections_override_garmin():
    j = {"mood": 6, "corrections": {"sleep_hours": 4.0}}
    a = compute({"sleep_hours": 8}, {"mood": 6}, [])
    b = compute({"sleep_hours": 8}, j, [])
    assert b.score < a.score


def test_no_data():
    r = compute(None, None, [])
    assert r.score is None and r.level == "unbekannt"
