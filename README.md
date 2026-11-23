<p align="center"><img src="branding/echowp-banner.png" alt="EchoWP" width="433"></p>

# EchoWP Trainer

Persönlicher Performance-Coach auf Basis deiner Garmin-Daten. Die Idee stammt aus dem
Video [„Garmin + Claude = mein eigener Performance-Coach“](https://www.youtube.com/watch?v=QeuDmuqpIpE):
Garmin sammelt die Daten, die App macht daraus einen Tagesplan, eine Trainingswoche und
einen Coach, mit dem man reden kann.

**Aktuelle Version: 1.0.0** (Android-App) – Download unter [Releases](https://github.com/EchoWP-Design/echowp-trainer/releases/latest)

![Dashboard](docs/img/heute.png)

## Was die App kann

- **Bereitschafts-Score (0–100)** aus Schlaf, HRV, Ruhepuls, Body Battery und deinem
  Gefühl. Das Gefühl zählt am meisten und deckelt den Score, wenn Garmin dich fit sieht,
  du dich aber nicht so fühlst. Ab 80 voll belastbar, unter 50 Last reduzieren.
- **Coaching-Briefing** für den Tag: wie geplant, angepasst (RPE, Sätze) oder Recovery.
- **Wochenplanung** auf Knopfdruck. Schwerpunkt Functional Fitness (Eigengewicht,
  Kettlebell, Gewichte), Ausdauer als Steigungsgehen auf dem Laufband, am Wochenende ein
  langer Marsch mit Rucksack. Knieschonend: kaum Laufen, keine Sprünge. 4-Wochen-Zyklus
  mit Deload, Entlastungswoche bei niedriger Bereitschaft. Plant um Termine aus deinem
  Kalender herum.
- **Kalender**: Der Plan steht als abonnierbarer iCal-Feed bereit (Google Kalender →
  „Per URL hinzufügen“).
- **Chat** mit dem Coach, auch um den Wochenplan umzubauen („Montag Termin, verschieb das“).
- **Journal** mit Gefühlsfeedback, Gewicht, Korrektur der Garmin-Werte, RPE und Feedback
  zu jedem Training sowie **Food Memory** (ohne Kalorienzählen).
- **Ernährungsziele** nach Mifflin-St Jeor oder nach Jans Excel-Formel, siehe
  [docs/ERNAEHRUNG.md](docs/ERNAEHRUNG.md).
- **Morgenroutine, Wochenziele und Streaks** als kleine Gamification.
- Läuft als **Web-App (PWA)** auf Handy und Desktop, installierbar auf dem Homescreen.

![Woche](docs/img/woche.png)

## Garmin

Drei Wege, Details in [docs/GARMIN.md](docs/GARMIN.md):

1. **Offizielle Garmin Connect Personal API** (empfohlen): Schlüssel in Garmin Connect
   erstellen, als `GARMIN_PERSONAL_API_KEY` eintragen, fertig.
2. Inoffizieller Garmin-Connect-Zugang über `garminconnect` als Reserve.
3. Import von FIT-Dateien und Garmin-Datenexport ohne Online-Zugang.

## KI-Coach

Mit `ANTHROPIC_API_KEY` formuliert Claude Briefing, Wochenplan und Chat-Antworten
(Standardmodell `claude-opus-5-5`, änderbar über `TRAINER_MODEL`). Ohne Schlüssel läuft
alles regelbasiert weiter. Der Wochenplan kommt dann direkt aus dem Planer.

## Android-App (ohne Server)

Die App in `app/` läuft komplett auf dem Handy: Sie holt die Garmin-Daten direkt über die
Personal API, rechnet Score, Plan und Ernährung selbst und spricht für den KI-Coach direkt mit
Claude. Daten bleiben auf dem Handy, die Schlüssel liegen im sicheren Speicher von Android.

**Installieren**
1. Unter [Releases](https://github.com/EchoWP-Design/echowp-trainer/releases) die neueste
   `EchoWP-Trainer.apk` auf dem Handy herunterladen und öffnen. Android fragt einmal, ob der
   Browser Apps installieren darf: erlauben.
2. App öffnen → Reiter **Daten** → Garmin Personal API Key einfügen → Speichern.
   Die App lädt sofort die letzten 14 Tage.
3. Im selben Reiter den Anthropic-API-Key für den KI-Coach einfügen.
4. Profil (Größe, Geburtsjahr, Geschlecht, Gewicht) eintragen, dann unter **Woche** planen.

Beim Öffnen synchronisiert die App automatisch, wenn der letzte Abruf älter als eine Stunde ist.

**Bauen:** GitHub Actions (`.github/workflows/android.yml`) erzeugt die Android-Ordner per
`flutter create`, passt sie mit `app/tool/patch_platforms.py` an, prüft (`flutter analyze`,
`flutter test`) und veröffentlicht die APKs als Release. Für Updates ohne Neuinstallation
braucht das Repo die Secrets `ANDROID_KEYSTORE_B64` und `ANDROID_KEYSTORE_PASSWORD`
(jede EchoWP-Schlüsseldatei, der Schlüsselname wird automatisch erkannt), sonst entsteht eine Testversion mit Debug-Signatur.

Lokal: `cd app && flutter pub get && flutter test`. Mit echten Schlüsseln:
`GARMIN_PERSONAL_API_KEY=… ANTHROPIC_API_KEY=… dart run tool/live_check.dart`.

## Server-Version starten

### Docker (Server, NAS, Raspberry Pi)

```bash
cp .env.example .env      # ausfüllen, mindestens TRAINER_TOKEN und GARMIN_PERSONAL_API_KEY
docker compose up -d --build
```

Dann `http://<server>:8080` öffnen. Daten liegen in `./data` (SQLite).
Für den Zugriff von unterwegs einen Reverse Proxy mit HTTPS davorsetzen.

### Lokal

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
set -a; source .env; set +a
python -m trainer.app            # http://localhost:8080
```

Zum Ausprobieren ohne Uhr: `TRAINER_DEMO=on python -m trainer.app`.

### Tests

```bash
pip install -r requirements-dev.txt
pytest
```

## Aufbau

| Pfad | Inhalt |
|---|---|
| `trainer/garmin/` | Datenquellen: Personal API, Garmin Connect, FIT/Export-Import, Demo |
| `trainer/readiness.py` | Bereitschafts-Score |
| `trainer/planner.py` | Regelbasierte Wochenplanung und Übungskatalog |
| `trainer/coach.py` | KI-Coach (Claude) mit Regel-Rückfall |
| `trainer/nutrition.py` | Kalorien- und Makrorechner |
| `trainer/service.py` | Fachlogik, verbindet alles |
| `trainer/app.py` | FastAPI: REST-API, iCal-Feed, Web-App |
| `trainer/static/` | Oberfläche (HTML/CSS/JS ohne Build), Icons, Schrift Inter |
| `tools/` | Generator für die App-Symbole |

## Design

EchoWP Corporate Design: Gelb `#FFD400` und Schwarz `#0A0A0A`, Schrift Inter, Wortmarke
„Echo“ mit Produktblock „Trainer“. App-Symbol: runder EchoWP-Elefant mit Echo-Bogen und
einer Kettlebell als Produktzeichen. Dunkel Gelb auf Schwarz, hell schwarze Akzente mit
schwarzen Kopfleisten.

## Hinweis

Die App ersetzt keine ärztliche Beratung. Bei Schmerzen, Krankheit oder Warnzeichen pausieren.
