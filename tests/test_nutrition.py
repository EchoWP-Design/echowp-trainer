import pytest

from trainer import nutrition


def test_jan_formula_matches_excel():
    # Werte wie in Rechner_Kalorien.xlsx bei 80 kg
    t = nutrition.calculate_jan(80)
    assert t.kcal == 2080          # B5 = B3*26
    assert t.protein_g == 160      # B6 = B3*2
    assert t.fat_g == 69           # B7 = B5/30 = 69,33
    assert t.fiber_g == 29         # B8 = B5*0,014 = 29,12
    assert t.carbs_g == 204        # B9 = (B5 - B6*4 - B7*9)/4 = 204
    assert t.water_l == 2.7        # B10 = B3/30 = 2,67


def test_mifflin_st_jeor():
    assert nutrition.mifflin_st_jeor(80, 180, 35, "m") == pytest.approx(1755)
    assert nutrition.mifflin_st_jeor(65, 168, 30, "w") == pytest.approx(1389)


def test_pal_steps():
    assert nutrition.pal_from_training(0) == 1.4
    assert nutrition.pal_from_training(4) == 1.7
    assert nutrition.pal_from_training(10) == 2.0


def test_science_mode_rules():
    t = nutrition.calculate_science(80, 180, 35, "m", training_h_week=6, goal="abnehmen",
                                    endurance_h_week=3, training_h_today=1)
    assert t.protein_g == 176                     # 2,2 g/kg im Defizit
    assert t.fiber_g >= 30
    assert t.fat_g >= 64                          # mindestens 0,8 g/kg
    assert t.water_l == pytest.approx(3.55, abs=0.1)
    assert t.protein_pct + t.fat_pct + t.carbs_pct == pytest.approx(100, abs=2)
    assert any("Defizit" in h for h in t.hints)


def test_fallback_to_jan_without_profile():
    t = nutrition.calculate(80, {"nutrition_mode": "wissenschaft"}, {})
    assert t.mode == "jan" and t.hints


def test_invalid_weight():
    with pytest.raises(ValueError):
        nutrition.calculate_jan(0)
