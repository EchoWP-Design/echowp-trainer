// Prüft Garmin und Claude mit echten Schlüsseln aus Umgebungsvariablen (nicht in CI).
import 'dart:io';

import 'package:echowp_trainer/logic/dates.dart';
import 'package:echowp_trainer/logic/readiness.dart';
import 'package:echowp_trainer/services/coach.dart';
import 'package:echowp_trainer/services/garmin.dart';

Future<void> main() async {
  final gk = Platform.environment['GARMIN_PERSONAL_API_KEY'];
  final ak = Platform.environment['ANTHROPIC_API_KEY'];
  if (gk != null) {
    final g = GarminClient(gk, loadToken: () async => null, saveToken: (_) async {});
    final d = addDays(dayOnly(DateTime.now()), -1);
    print('Garmin ${iso(d)}: ${await g.fetchDaily(d)}');
    final acts = await g.fetchActivities(addDays(d, -180), d);
    print('Aktivitäten 180 Tage: ${acts.length}${acts.isEmpty ? '' : ', letzte: ${acts.first['date']} ${acts.first['kind']}'}');
  }
  if (ak != null) {
    final c = CoachClient(ak, model: 'claude-haiku-5-5');
    final r = computeReadiness({'sleep_hours': 7.5}, null, []);
    print('Claude: ${(await c.briefing({'test': true}, r, [])).text.substring(0, 80)}');
  }
}
