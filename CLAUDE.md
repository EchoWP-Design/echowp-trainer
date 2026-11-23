# EchoWP Trainer – Hinweise für Claude

- Sprache: Deutsch (UI, Texte, Commit-Nachrichten dürfen Deutsch sein).
- Corporate Design strikt einhalten: Skill `echowp-corporate-design` (Gelb #FFD400, Schwarz #0A0A0A, Elefant). Gelbe Schrift nie auf Weiß.
- Training: Grundlage sind bis zu 4 vom Nutzer gewählte Disziplinen (`app/lib/logic/disciplines.dart`). Jan selbst: Functional Fitness, Steigungsgehen, Märsche/Rucking, knieschonend (kaum Laufen, keine Sprünge, keine tiefen Ausfallschritte). Die App geht auch an Familie und Freunde: keine Jan-Vorgaben als Standard für neue Installationen.
- Ernährung: Modus "jan" muss Jans Excel-Formeln exakt behalten (Test `tests/test_nutrition.py`).
- Garmin: zuerst Personal API (`trainer/garmin/personal_api.py`), Reserve `garminconnect`, Import FIT/Export.
- Web-Oberfläche ohne Build-Toolchain: reines HTML/CSS/JS in `trainer/static/`.
- Android-App in `app/` (Flutter, läuft ohne Server). Logik in `app/lib/logic/` muss zur Python-Logik passen (gleiche Formeln, Tests in `app/test/`). Plattformordner nicht ins Repo, Build nur in GitHub Actions. Schlüssel nie ins Repo.
- Tests: `pytest` und `cd app && flutter test` (keine Netzwerkzugriffe in Tests).
- Zu Beginn `HANDOFF.md` lesen; am Ende einer langen Sitzung `/handoff` (`.claude/commands/handoff.md`).
