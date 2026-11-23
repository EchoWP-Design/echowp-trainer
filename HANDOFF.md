# Übergabe EchoWP Trainer – Stand 23.11.2026

## Ziel der Sitzung
Trainer-App von Jans Garmin-Coach zur eigenständigen Android-App ausbauen, die Jan auch an
Familie und Freunde weitergibt.

## Erledigt (App 1.1.0 → 1.4.0, alle Builds signiert, Zertifikat f6868ac2…)
- 1.1.0/1.1.1: Essens-Tagebuch, Food Memory, Barcode-Scanner (Open Food Facts), rechtliche
  Hinweise (Erststart-Dialog, Daten → Rechtliches, LICENSE), Update-Abruf wie EchoWP-Mail.
- 1.2.0: Health Connect für Amazfit (Zepp), Suunto u. a. (`app/lib/services/health_connect.dart`),
  Startseite „Heute gemessen“ mit Schritten und Ruhe/Aktiv/Gesamt-kcal, Kalorienziel aus
  Uhr-Verbrauch (Ruhe 7-Tage-Schnitt + Aktiv heute), minSdk 26.
- 1.3.0: Bis zu 4 Disziplinen mit Anzahl/Woche (`app/lib/logic/disciplines.dart`, 17 Arten),
  Planer/Wochenziele/Coach darauf umgestellt, Schalter „Knieschonend“. Jans Installation
  wird migriert (4× Functional, 3× Steigung, 1× Marsch, knieschonend), neue Installationen neutral.
- 1.4.0 (Build 10): Essen fotografieren → Claude schätzt. Foto wird nach dem Einlesen gelöscht
  (inkl. Original vor Verkleinerung), EXIF/GPS entfernt (`app/lib/services/photo.dart`).

- 1.4.1 (Build 11): Bugfix „12 kcal Ziel“ (unplausible Uhr-Ruhewerte → Formel mit Hinweis),
  gelöschter Garmin-Key (Token HTTP 404) wird gemeldet statt still 0 Tage zu laden.

## Offen / nächster Schritt
- Jan muss einen neuen Garmin Personal API Key eintragen (alter gelöscht).
- Jans Rückmeldung auf dem Handy: echter Barcode-Scan, Health Connect mit Amazfit/Suunto,
  Foto-Schätzung mit echtem Essen, Migration der Disziplinen.
- Server-/Web-Version (`trainer/`, Python) hat noch feste Ziele und keine Disziplinen,
  kein Health Connect, keine Fotos. Klären, ob sie noch gebraucht wird (sonst so lassen).
- Für Weitergabe an andere: eigener Anthropic-Key je Person nötig; ggf. Datenschutzerklärung.

## Entscheidungen
- Zepp/Suunto haben keine offene Schnittstelle für Privatnutzer → nur Health Connect.
- Garmin hat Vorrang; Health Connect füllt Lücken, Schritte/kcal = höchster Wert einer App,
  Trainings mit Start ≤ 10 min Abstand gelten als doppelt.
- `health` fest auf 13.3.1 (ab 13.3.2 Konflikt mit flutter_secure_storage 9; v10+ nicht
  eingeführt, weil Speicherformat wechselt und Keys verloren gehen könnten).
- image_picker ^1.2.4; Release-Lint aus (`checkReleaseBuilds = false` in patch_platforms.py),
  weil Android-Lint an `ExifDataCopier.java` abstürzt.

## Bekannte Probleme
- Garmin Personal API Key aus der Sitzung liefert Token-HTTP 404 (vermutlich von Jan neu
  erzeugt) → Live-Prüfung Garmin nicht mehr möglich, Kalorienfelder nur gegen gespeicherte
  Antwort vom 22.11. getestet.
- Open Food Facts ist aus der Cloud-Sandbox gesperrt, nur mit Beispieldaten getestet.
- Health Connect und Kamera nur mit Fakes/Beispieldaten getestet (kein Gerät).

## Zustand
- Branch `main`, letzter Code-Commit `09a282c`, Build grün:
  Release `app-v1.4.1-build-11`. Tests: 62 grün (`cd app && flutter test`).
- Flutter 3.50.1 ließ sich in dieser Sitzung lokal nutzen (storage.googleapis.com und
  pub.dev erreichbar) → `flutter analyze --no-fatal-infos lib test` und `flutter test` lokal.
