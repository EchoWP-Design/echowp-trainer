import 'package:echowp_trainer/app_state.dart';
import 'package:echowp_trainer/logic/dates.dart';
import 'package:echowp_trainer/logic/disciplines.dart';
import 'package:echowp_trainer/logic/planner.dart';
import 'package:echowp_trainer/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _settings(List<(String, int)> d, {bool knee = false}) => Map<String, dynamic>.from(defaultSettings)
  ..['disciplines'] = [
    for (final (k, n) in d) {'key': k, 'per_week': n}
  ]
  ..['knee_friendly'] = knee;

void main() {
  final ws = DateTime(2026, 11, 30); // Aufbauwoche

  test('höchstens vier Disziplinen, unbekannte und doppelte fallen weg', () {
    final g = disciplinesFrom(_settings([
      ('hyrox', 2),
      ('hyrox', 3),
      ('gibtsnicht', 1),
      ('jogging', 2),
      ('rudern', 1),
      ('yoga', 1),
      ('marsch', 1),
    ]));
    expect(g.map((x) => x.discipline.key), ['hyrox', 'jogging', 'rudern', 'yoga']);
    expect(g.first.perWeek, 2);
  });

  test('alte Einstellung (goals) wird übernommen', () {
    final g = disciplinesFrom({
      'goals': {'strength': 4, 'cardio': 3, 'march': 1}
    });
    expect([for (final x in g) '${x.discipline.key}:${x.perWeek}'], ['functional:4', 'steigung:3', 'marsch:1']);
  });

  test('Plan enthält jede Disziplin so oft wie gewählt', () {
    final p =
        buildWeek(ws, _settings([('hyrox', 2), ('jogging', 2), ('rudern', 1), ('spazieren', 2)]), avgReadiness: 75);
    int n(bool Function(PlannedSession) f) => p.sessions.where(f).length;
    expect(n((s) => s.title.startsWith('Hyrox')), 2);
    expect(n((s) => s.kind == 'lauf'), 2);
    expect(n((s) => s.title == 'Rudern'), 1);
    expect(n((s) => s.kind == 'gehen'), 2);
    expect(n((s) => s.kind == 'mobility'), 1);
    expect(p.unplaced, isEmpty);
    // Höchstens zwei Einheiten am Tag
    for (var i = 0; i < 7; i++) {
      expect(p.sessions.where((s) => s.date == iso(addDays(ws, i))).length, lessThanOrEqualTo(2));
    }
  });

  test('knieschonend: Hyrox ohne Laufen, Joggen mit Hinweis', () {
    final p = buildWeek(ws, _settings([('hyrox', 2), ('jogging', 1)], knee: true), avgReadiness: 75);
    final hyrox = p.sessions.where((s) => s.title.startsWith('Hyrox')).toList();
    expect(hyrox.map((s) => s.focus).join(), contains('Rudergerät'));
    final sim = hyrox.firstWhere((s) => s.title == 'Hyrox Simulation');
    expect(sim.exercises.first['name'], 'Rudern statt Laufen');
    expect(p.sessions.firstWhere((s) => s.kind == 'lauf').focus, contains('Knieschmerz'));
    final text = p.sessions.expand((s) => s.exercises).map((e) => e['name']).join(' ');
    expect(text, isNot(contains('Lunges')));
  });

  test('Wochenziele: jede Aktivität zählt nur einmal, genaue Disziplin zuerst', () {
    final goals = disciplinesFrom(_settings([('functional', 3), ('rudern', 1), ('spazieren', 2), ('marsch', 1)]));
    final done = countDone([
      {'kind': 'kraft', 'type': 'strength_training'},
      {'kind': 'cardio', 'type': 'indoor_rowing'},
      {'kind': 'gehen', 'type': 'walking', 'duration_s': 5400},
      {'kind': 'gehen', 'type': 'walking', 'duration_s': 1800},
    ], goals);
    expect(done, {'functional': 1, 'rudern': 1, 'spazieren': 1, 'marsch': 1});
  });

  test('Bestehende Installation behält Jans Auswahl, neue startet neutral', () {
    final old = Store.memory()..section('metrics')['2026-11-20'] = {'steps': 1};
    final st = AppState(old, MemorySecrets())..migrateSettings();
    expect(st.disciplines.map((g) => g.discipline.key), ['functional', 'steigung', 'marsch']);
    expect(st.store.setting('knee_friendly'), isTrue);
    expect(st.store.setting('constraints'), contains('Knie'));

    final fresh = AppState(Store.memory(), MemorySecrets())..migrateSettings();
    fresh.store.setSetting('notice_ok', true);
    fresh.store.section('metrics')['2026-11-20'] = {'steps': 1};
    fresh.migrateSettings(); // zweiter Start: bleibt neutral
    expect(fresh.disciplines.map((g) => g.discipline.key), ['functional', 'kardio', 'spazieren']);
    expect(fresh.store.setting('knee_friendly'), isFalse);
  });
}
