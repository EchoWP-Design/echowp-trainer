import 'dart:convert';

import 'package:echowp_trainer/app_state.dart';
import 'package:echowp_trainer/logic/dates.dart';
import 'package:echowp_trainer/logic/food.dart';
import 'package:echowp_trainer/main.dart';
import 'package:echowp_trainer/services/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

final _now = DateTime(2026, 11, 23, 10, 0);

String _jwt() {
  final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': _now.millisecondsSinceEpoch ~/ 1000 + 86400})));
  return 'h.${payload.replaceAll('=', '')}.s';
}

/// Simuliert Garmin Personal API und Anthropic API ohne Netzwerk.
MockClient fakeApis({List<String>? log}) => MockClient((req) async {
      log?.add('${req.method} ${req.url.path}');
      final p = req.url.path;
      if (p.endsWith('/personal-api-key/token')) {
        expect(req.headers['Authorization'], 'ApiKey garmin-test-key');
        return http.Response(_jwt(), 200);
      }
      if (req.url.host == 'personal.connectapi.garmin.com') {
        expect(req.headers['Authorization'], startsWith('Bearer '));
      }
      if (p == '/sleep-service/sleep/dailySleep') {
        return http.Response(
            jsonEncode({
              'sleepTimeSeconds': 27000,
              'sleepScores': {
                'overall': {'value': 82}
              }
            }),
            200);
      }
      if (p.startsWith('/hrv-service/hrv/')) {
        return http.Response(
            jsonEncode({
              'hrvSummary': {'lastNightAvg': 48}
            }),
            200);
      }
      if (p == '/usersummary-service/v2/dailysummaries') {
        final d = req.url.queryParameters['startDate'];
        return http.Response(
            jsonEncode({
              'data': [
                {
                  'calendarDate': d,
                  'heartRate': {'restingValue': 50},
                  'stress': {'avgLevel': 30},
                  'bodyBattery': {'maxValue': 80}
                }
              ]
            }),
            200);
      }
      if (p == '/wellness-service/wellness/bodyBattery/reports/daily') return http.Response('[]', 200);
      if (p == '/activitylist-service/activities/search/activities') {
        return http.Response(
            jsonEncode([
              {
                'activityId': 7,
                'activityName': 'Rucking Wald',
                'startTimeLocal': '2026-11-22 09:00:00',
                'activityType': {'typeKey': 'rucking'},
                'duration': 6000.0,
                'distance': 10000.0,
                'averageHR': 118
              }
            ]),
            200);
      }
      if (req.url.host == 'api.anthropic.com') {
        expect(req.headers['x-api-key'], 'claude-test-key');
        final body = jsonDecode(req.body) as Map;
        final schema = (body['output_config'] as Map)['format'];
        final text = schema != null
            ? jsonEncode({
                'phase': 'Deload',
                'summary': 'Ruhige Woche.',
                'rationale': 'Score niedrig.',
                'questions': ['Wie geht es dem Knie?'],
                'sessions': [
                  {
                    'date': '2026-11-24',
                    'start': '18:00',
                    'end': '19:00',
                    'kind': 'kraft',
                    'title': 'Kettlebell Ganzkörper',
                    'focus': 'locker',
                    'rpe': 6,
                    'exercises': [
                      {'name': 'Kettlebell Swing', 'detail': '3 × 15 @ RPE 6'}
                    ]
                  }
                ]
              })
            : 'Heute locker bleiben.';
        return http.Response(
            jsonEncode({
              'stop_reason': 'end_turn',
              'content': [
                {'type': 'text', 'text': text}
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('nicht gefunden', 404);
    });

Future<AppState> makeState({bool keys = true, List<String>? log}) async {
  final st = AppState(
    Store.memory(),
    MemorySecrets(keys ? {'garmin_key': 'garmin-test-key', 'anthropic_key': 'claude-test-key'} : {}),
    httpClient: fakeApis(log: log),
    clock: () => _now,
  );
  await st.init();
  return st;
}

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  test('Sync holt Tageswerte und Aktivitäten', () async {
    final log = <String>[];
    final st = await makeState(log: log);
    final msg = await st.sync();
    expect(msg, contains('3 Tage'));
    final m = st.metricsFor('2026-11-23')!;
    expect(m['sleep_hours'], 7.5);
    expect(m['hrv_ms'], 48);
    expect(m['resting_hr'], 50);
    expect(m['body_battery'], 80);
    expect(st.activities(DateTime(2026, 11, 16), DateTime(2026, 11, 23)).single['kind'], 'gehen');
    // Token wird nur einmal geholt und wiederverwendet
    expect(log.where((l) => l.endsWith('/token')).length, 1);
    expect(await st.secrets.read('garmin_token'), isNotNull);
    expect(st.goalsFor(DateTime(2026, 11, 22)).firstWhere((g) => g.key == 'march').done, 1);
  });

  test('Ohne Key kein Sync, verständliche Meldung', () async {
    final st = await makeState(keys: false);
    expect(await st.sync(), isNull);
    expect(st.lastError, contains('Garmin Personal API Key'));
  });

  test('Coach plant die Woche, Briefing und Chat', () async {
    final st = await makeState();
    await st.sync();
    final ws = weekStartOf(st.today);
    final plan = await st.planWeek(ws);
    expect(plan!.source, 'claude');
    expect(plan.sessions.single.title, 'Kettlebell Ganzkörper');
    st.setSessionStatus(ws, 0, 'erledigt');
    expect(st.planFor(ws)!.sessions.single.status, 'erledigt');

    final b = await st.refreshBriefing(st.today);
    expect(b!.source, 'claude');
    expect(st.briefingFor(st.today).text, 'Heute locker bleiben.');

    await st.chat('Was mache ich heute?');
    expect(st.chatHistory('coach').length, 2);
    expect(st.chatHistory('coach').last['content'], 'Heute locker bleiben.');
  });

  test('Ohne Anthropic-Key regelbasierter Plan', () async {
    final st = AppState(Store.memory(), MemorySecrets(), clock: () => _now);
    await st.init();
    final plan = await st.planWeek(weekStartOf(st.today));
    expect(plan!.source, 'regeln');
    expect(plan.sessions, isNotEmpty);
    expect(st.briefingFor(st.today).source, 'regeln');
  });

  test('Journal beeinflusst Score und Gewicht', () async {
    final st = await makeState();
    await st.sync();
    final before = st.readinessFor(st.today).score!;
    st.saveJournal(
        '2026-11-23', {'mood': 2, 'energy': 1, 'motivation': 2, 'soreness': 9, 'stress': 9, 'weight_kg': 84.5});
    expect(st.readinessFor(st.today).score, lessThan(before));
    expect(st.latestWeight(st.today), 84.5);
    expect(st.nutritionFor(st.today), isNotNull);
  });

  testWidgets('Alle Bereiche öffnen ohne Überlauf auf schmalem Handy', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 760 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final st = await makeState();
    await tester.runAsync(() async {
      await st.sync();
      await st.planWeek(weekStartOf(st.today));
    });
    st.addFood('2026-11-23', [
      const FoodEntry(
          id: '',
          date: '',
          time: '',
          name: 'Sehr langer Produktname Skyr Natur Hochprotein Vanille',
          amount: '500 g',
          kcal: 315,
          protein: 55)
    ]);
    st.saveJournal('2026-11-23', {'weight_kg': 84.0, 'mood': 6});
    st.store.setSetting('notice_ok', true);
    await tester.pumpWidget(TrainerApp(state: st));
    await tester.pumpAndSettle();
    expect(find.text('BEREITSCHAFT'), findsOneWidget);
    for (final tab in ['Woche', 'Essen', 'Journal', 'Coach', 'Daten', 'Heute']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hinweis beim ersten Start muss bestätigt werden', (tester) async {
    final st = await makeState();
    await tester.pumpWidget(TrainerApp(state: st));
    await tester.pumpAndSettle();
    expect(find.text('Bevor es losgeht'), findsOneWidget);
    expect(find.textContaining('kein Medizinprodukt'), findsOneWidget);
    await tester.tap(find.text('Verstanden'));
    await tester.pumpAndSettle();
    expect(find.text('Bevor es losgeht'), findsNothing);
    expect(st.store.setting('notice_ok'), isTrue);
    await tester.tap(find.text('Daten').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Open-Source-Lizenzen'), 400,
        scrollable: find.byType(Scrollable).hitTestable().first);
    expect(find.text('Open-Source-Lizenzen'), findsOneWidget);
    expect(find.text('Nach Updates suchen'), findsOneWidget);
  });
}
