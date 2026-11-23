# EchoWP Trainer – Hinweise für Claude

- Sprache: Deutsch (UI, Texte, Commit-Nachrichten dürfen Deutsch sein).
- Corporate Design strikt einhalten: Skill `echowp-corporate-design` (Gelb #FFD400, Schwarz #0A0A0A, Elefant). Gelbe Schrift nie auf Weiß.
- Training: Functional Fitness, Eigengewicht, Kettlebell, Gewichte, Steigungsgehen auf dem Laufband, Märsche/Rucking. Wegen Kniebeschwerden kaum Laufen, keine Sprünge, keine tiefen Ausfallschritte.
- Ernährung: Modus "jan" muss Jans Excel-Formeln exakt behalten (Test `tests/test_nutrition.py`).
- Garmin: zuerst Personal API (`trainer/garmin/personal_api.py`), Reserve `garminconnect`, Import FIT/Export.
- Keine Build-Toolchain im Frontend: reines HTML/CSS/JS in `trainer/static/`.
- Tests: `pytest` (keine Netzwerkzugriffe in Tests).
