/// Rechtliche Hinweise: Gesundheits-Hinweis, Datenschutz, Quellen, Marken.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

const healthNotice = 'EchoWP Trainer ist kein Medizinprodukt und ersetzt keine ärztliche Beratung, Diagnose oder '
    'Behandlung. Bereitschafts-Score, Trainingspläne, KI-Antworten und Kalorienwerte sind Schätzungen und können '
    'falsch sein. Bei Schmerzen, Krankheit, Brustschmerz, Schwindel oder anderen Warnzeichen das Training abbrechen '
    'und ärztlich abklären lassen. Nutzung auf eigene Verantwortung.';

const privacyNotice = 'Alle Daten bleiben auf diesem Handy, Schlüssel im sicheren Speicher von Android. '
    'Daten gehen nur an Garmin (Abruf deiner Daten), an Anthropic (nur mit eingetragenem Key: Briefing, Wochenplan, '
    'Chat und KI-Schätzung beim Essen, dabei die nötigen Trainings-, Gesundheits- und Essensdaten) und an '
    'Open Food Facts (nur der gescannte Barcode). Keine eigenen Server, keine Werbung, kein Tracking.';

const offAttribution =
    'Produktdaten: Open Food Facts (openfoodfacts.org), Datenbank unter ODbL, Inhalte unter CC BY-SA 4.0.';

const trademarkNotice = 'Garmin, Garmin Connect und Body Battery sind Marken von Garmin Ltd., Claude ist eine Marke '
    'von Anthropic. EchoWP Trainer ist ein unabhängiges Projekt und mit keinem dieser Unternehmen verbunden.';

/// Hinweis beim ersten Start, muss einmal bestätigt werden.
Future<void> showFirstStartNotice(BuildContext context) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: echoSurface,
          title: const Text('Bevor es losgeht'),
          content: const SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Gesundheit', style: TextStyle(color: echoYellow, fontWeight: FontWeight.w900)),
              SizedBox(height: 4),
              Text(healthNotice, style: TextStyle(height: 1.4)),
              SizedBox(height: 12),
              Text('Datenschutz', style: TextStyle(color: echoYellow, fontWeight: FontWeight.w900)),
              SizedBox(height: 4),
              Text(privacyNotice, style: TextStyle(height: 1.4)),
              SizedBox(height: 12),
              Text('Alles jederzeit nachlesen unter Daten → Rechtliches.',
                  style: TextStyle(color: echoMuted, fontSize: 12)),
            ]),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Verstanden')),
          ],
        ),
      ),
    );

/// Dauerhafter Bereich im Reiter „Daten“.
class LegalSection extends StatelessWidget {
  const LegalSection({super.key});

  @override
  Widget build(BuildContext context) {
    Widget block(String title, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(text, style: const TextStyle(color: echoMuted, fontSize: 13, height: 1.4)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      block('Kein Medizinprodukt', healthNotice),
      block('Datenschutz', privacyNotice),
      block(
          'Quellen',
          '$offAttribution\nSchrift Inter: SIL Open Font License.\nQuellcode: MIT-Lizenz, '
              'github.com/EchoWP-Design/echowp-trainer'),
      block('Marken', trademarkNotice),
      OutlinedButton.icon(
        onPressed: () => showLicensePage(
          context: context,
          applicationName: 'EchoWP Trainer',
          applicationLegalese: '© 2026 EchoWP-Design · MIT-Lizenz',
        ),
        icon: const Icon(Icons.description_outlined),
        label: const Text('Open-Source-Lizenzen'),
      ),
    ]);
  }
}
