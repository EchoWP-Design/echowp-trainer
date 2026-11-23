# Garmin anbinden

Die App kann ihre Daten auf drei Wegen bekommen. Du brauchst nur einen davon.

## 1. Offizielle Personal API (empfohlen)

Seit Herbst 2026 bietet Garmin Privatpersonen einen eigenen API-Schlüssel für die
eigenen Daten an. Kein Antrag, keine Firma nötig.

1. In Garmin Connect Web anmelden und
   [Einstellungen → Personal API Key](https://connect.garmin.com/app/settings/personalApiToken) öffnen.
2. **Create Key**, Nutzungsbedingungen bestätigen, Laufzeit wählen (30 Tage bis 1 Jahr).
3. Den Schlüssel sofort kopieren, er wird nur einmal angezeigt.
4. In der `.env` eintragen: `GARMIN_PERSONAL_API_KEY=...` und die App neu starten.

Die App tauscht den Schlüssel gegen ein Zugriffstoken (24 Stunden gültig) und
speichert es in `data/garmin-personal-token.json`. Etwa eine Woche vor Ablauf des
Schlüssels schickt Garmin eine Erinnerungsmail; dann einen neuen erstellen und
in der `.env` ersetzen.

Gelesen werden: Schlaf (Dauer, Schlafscore), HRV, Tageszusammenfassung
(Ruhepuls, Stress, Schritte), Body Battery und Aktivitäten.

**Falls ein Wert fehlt:** Garmin beschreibt die Antwortfelder nicht vollständig.
`python -m trainer.garmin_probe 2026-11-22` speichert die Rohdaten eines Tages in
`data/garmin-probe-2026-11-22.json`. Damit lässt sich die Zuordnung in
`trainer/garmin/personal_api.py` anpassen. Die Datei enthält Gesundheitsdaten,
also nicht öffentlich teilen.

Quellen: [Personal API](https://developer.garmin.com/gc-developer-program/personal/personal-api/),
[FAQ](https://developer.garmin.com/gc-developer-program/personal/personal-faq/),
[Swagger](https://developer.garmin.com/gc-developer-program/personal/swagger-docs/),
[Garmins Beispielclient](https://github.com/garmin/connect-personal-api-python).

## 2. Inoffizieller Garmin-Connect-Zugang (Reserve)

Über die Bibliothek [`garminconnect`](https://github.com/cyberjunky/python-garminconnect),
die sich wie die Garmin-App anmeldet. Liefert mehr Werte (z. B. Garmins eigene
Trainingsbereitschaft), kann aber jederzeit brechen, wenn Garmin intern etwas ändert.

```bash
python -m trainer.garmin_login   # fragt E-Mail, Passwort und ggf. den Zwei-Faktor-Code
```

Danach liegen Tokens in `data/garmin-tokens`, das Passwort muss nicht in der `.env` bleiben.
Wird nur genutzt, wenn kein `GARMIN_PERSONAL_API_KEY` gesetzt ist.

## 3. Import ohne Online-Zugang

Unter **Daten** in der App:

- **FIT-Dateien** direkt von der Uhr: per USB anschließen, Ordner `GARMIN/Activity`.
- **Garmin-Datenexport** (ZIP) aus dem Garmin-Konto (Datenschutz → Daten exportieren).
  Die App liest daraus Aktivitäten (`.fit`) sowie Schlaf- und Tageswerte
  (`*_sleepData.json`, `UDSFile_*.json`).

## Business-Programm (nicht nötig)

Das [Garmin Connect Developer Program](https://developer.garmin.com/gc-developer-program/)
mit Health-, Activity- und Training-API ist für Firmen gedacht, die Apps für viele
Nutzer bauen. Es braucht einen Antrag mit Prüfung und kann Lizenzkosten haben.
Interessant wäre es nur, wenn der Coach später Workouts direkt auf die Uhr schicken
soll (Training API) oder EchoWP Trainer für andere Nutzer angeboten wird.
