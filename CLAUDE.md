# EchoWP Trainer – Hinweise für Claude

- Sprache: Deutsch (UI, Texte, Commit-Nachrichten dürfen Deutsch sein).
- Corporate Design strikt einhalten: Skill `echowp-corporate-design` (Gelb #FFD400, Schwarz #0A0A0A, Elefant). Gelbe Schrift nie auf Weiß.
- Training: Functional Fitness, Eigengewicht, Kettlebell, Gewichte, Steigungsgehen auf dem Laufband, Märsche/Rucking. Wegen Kniebeschwerden kaum Laufen, keine Sprünge, keine tiefen Ausfallschritte.
- Ernährung: Modus "jan" muss Jans Excel-Formeln exakt behalten (Test `tests/test_nutrition.py`).
- Garmin: zuerst Personal API (`trainer/garmin/personal_api.py`), Reserve `garminconnect`, Import FIT/Export.
- Web-Oberfläche ohne Build-Toolchain: reines HTML/CSS/JS in `trainer/static/`.
- Android-App in `app/` (Flutter, läuft ohne Server). Logik in `app/lib/logic/` muss zur Python-Logik passen (gleiche Formeln, Tests in `app/test/`). Plattformordner nicht ins Repo, Build nur in GitHub Actions. Schlüssel nie ins Repo.
- Tests: `pytest` und `cd app && flutter test` (keine Netzwerkzugriffe in Tests).
