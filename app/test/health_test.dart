import 'package:echowp_trainer/app_state.dart';
import 'package:echowp_trainer/logic/nutrition.dart';
import 'package:echowp_trainer/services/garmin.dart';
import 'package:echowp_trainer/services/health_connect.dart';
import 'package:echowp_trainer/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _now = DateTime(2026, 11, 23, 18, 0);
const _zepp = 'com.huami.watch.hmwatchmanager';
const _suunto = 'com.stt.android.suunto';
const _garminApp = 'com.garmin.android.apps.connectmobile';

DateTime _t(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m);

class _FakeHealth implements HealthReader {
  final List<HcPoint> points;
  bool granted;
  _FakeHealth(this.points, {this.granted = true});
  @override
  Future<bool> available() async => true;
  @override
  Future<void> install() async {}
  @override
  Future<bool> authorize() async => granted;
  @override
  Future<List<HcPoint>> read(DateTime start, DateTime end) async => points;
}

final _points = [
  HcPoint('STEPS', 4000, _t(23, 8), _t(23, 9), _zepp),
  HcPoint('STEPS', 5000, _t(23, 12), _t(23, 13), _zepp),
  HcPoint('STEPS', 6000, _t(23, 8), _t(23, 13), _suunto), // gleiche Zeit, andere App: nicht addieren
  HcPoint('ACTIVE_ENERGY_BURNED', 300, _t(23, 8), _t(23, 9), _zepp),
  HcPoint('ACTIVE_ENERGY_BURNED', 150, _t(23, 17), _t(23, 18), _zepp),
  HcPoint('BASAL_ENERGY_BURNED', 1900, _t(23, 0), _t(23, 0), _zepp),
  HcPoint('RESTING_HEART_RATE', 52, _t(23, 7), _t(23, 7), _zepp),
  HcPoint('HEART_RATE_VARIABILITY_RMSSD', 40, _t(23, 3), _t(23, 3), _zepp),
  HcPoint('HEART_RATE_VARIABILITY_RMSSD', 50, _t(23, 4), _t(23, 4), _zepp),
  HcPoint('SLEEP_SESSION', 0, _t(22, 23), _t(23, 6, 30), _zepp),
  HcPoint('WORKOUT', 0, _t(23, 17, 2), _t(23, 18), _suunto, id: 'w1', workout: 'WALKING', distanceM: 6000, kcal: 450),
  HcPoint('WORKOUT', 0, _t(23, 7), _t(23, 7, 45), _zepp, id: 'w2', workout: 'WEIGHTLIFTING'),
];

void main() {
  group('Health Connect', () {
    test('Tageswerte: Summe je App, höchste App gewinnt', () {
      final d = aggregateDaily(_points)['2026-11-23']!;
      expect(d['steps'], 9000);
      expect(d['steps_src'], 'Amazfit');
      expect(d['active_kcal'], 450);
      expect(d['rest_kcal'], 1900);
      expect(d['resting_hr'], 52);
      expect(d['hrv_ms'], 45);
      expect(d['sleep_hours'], 7.5);
    });

    test('Ruhekalorien aus Gesamt minus Aktiv', () {
      final d = aggregateDaily([
        HcPoint('TOTAL_CALORIES_BURNED', 2600, _t(23, 0), _t(23, 23), _suunto),
        HcPoint('ACTIVE_ENERGY_BURNED', 500, _t(23, 0), _t(23, 23), _suunto),
      ])['2026-11-23']!;
      expect(d['rest_kcal'], 2100);
    });

    test('Quellen erkennen', () {
      expect(sourceLabel(_zepp), 'Amazfit');
      expect(sourceLabel(_suunto), 'Suunto');
      expect(sourceLabel(_garminApp), 'Garmin');
    });

    test('Trainings werden Aktivitäten', () {
      final acts = workoutsToActivities(_points);
      expect(acts, hasLength(2));
      final walk = acts.firstWhere((a) => a['id'] == 'hc-w1');
      expect(walk['kind'], 'gehen');
      expect(walk['start_time'], '17:02');
      expect(walk['distance_m'], 6000);
      expect(walk['name'], 'Gehen (Suunto)');
      expect(acts.firstWhere((a) => a['id'] == 'hc-w2')['kind'], 'kraft');
    });

    test('Zusammenführen: Garmin zuerst, Schritte/Kalorien höchster Wert', () {
      final m = mergeMetrics(
        {'date': '2026-11-23', 'steps': 3000, 'resting_hr': 50, 'rest_kcal': 2200, 'active_kcal': 100},
        {'date': '2026-11-23', 'steps': 9000, 'steps_src': 'Amazfit', 'resting_hr': 58, 'hrv_ms': 45},
      )!;
      expect(m['steps'], 9000);
      expect(m['steps_src'], 'Amazfit');
      expect(m['resting_hr'], 50);
      expect(m['hrv_ms'], 45);
      expect(m['total_kcal'], 2300);
    });
  });

  group('Garmin-Kalorien', () {
    test('Ruhe + Aktiv = Gesamt aus der Personal API', () {
      final m = parseDaily(
          '2026-11-22',
          null,
          null,
          {
            'data': [
              {
                'calendarDate': '2026-11-22',
                'movement': {
                  'steps': {'goal': 4300, 'value': 2659}
                },
                'calories': {'burnedResting': 2228, 'burnedActive': 61, 'burnedTotal': 2289},
              }
            ]
          },
          null);
      expect([m['steps'], m['rest_kcal'], m['active_kcal'], m['total_kcal']], [2659, 2228, 61, 2289]);
    });
  });

  group('Kalorienziel aus Verbrauch', () {
    test('Jan-Modus: Ruhe + Aktiv, Makros nach Jans Regeln', () {
      final t = withBurn(calculateJan(80), restKcal: 1800, activeKcal: 600);
      expect(t.kcal, 2400);
      expect(t.proteinG, 160);
      expect(t.fatG, 80);
      expect(t.fiberG, 34);
      expect([t.restKcal, t.activeKcal], [1800, 600]);
    });

    test('Ziel Abnehmen zieht 15 % ab', () {
      final t = withBurn(calculateJan(80), restKcal: 2000, activeKcal: 0, goal: 'abnehmen');
      expect(t.kcal, 1700);
    });

    test('App: Ruhe als 7-Tage-Schnitt, Aktiv von heute, abschaltbar', () async {
      final st = AppState(Store.memory(), MemorySecrets(), clock: () => _now);
      st.store.setSetting('profile', {'weight_kg': 80, 'nutrition_mode': 'jan'});
      st.store.section('metrics')['2026-11-22'] = {'date': '2026-11-22', 'rest_kcal': 2000};
      st.store.section('metrics')['2026-11-21'] = {'date': '2026-11-21', 'rest_kcal': 2200};
      st.store.section('metrics')['2026-11-23'] = {'date': '2026-11-23', 'rest_kcal': 1500, 'active_kcal': 400};
      final t = st.nutritionFor(st.today)!;
      expect(t.restKcal, 2100);
      expect(t.activeKcal, 400);
      expect(t.kcal, 2500);
      st.store.setSetting('profile', {'weight_kg': 80, 'nutrition_mode': 'jan', 'kcal_from_burn': false});
      expect(st.nutritionFor(st.today)!.kcal, 2080);
    });
  });

  test('Gelöschter Garmin-Key: Sync meldet es, statt still 0 Tage zu laden', () async {
    final client = MockClient((req) async =>
        http.Response('{"message":"Personal API Key with ID x does not exist.","error":"NotFoundException"}', 404));
    final st = AppState(Store.memory(), MemorySecrets({'garmin_key': 'alt'}), httpClient: client, clock: () => _now);
    await st.init();
    expect(await st.sync(), isNull);
    expect(st.lastError, contains('gibt es nicht mehr'));
    expect(st.lastSync!['ok'], isFalse);
  });

  group('Unplausible Uhrdaten', () {
    test('Ruhe 9 + Aktiv 5 kcal: Formel statt 12-kcal-Ziel, mit Hinweis', () {
      final st = AppState(Store.memory(), MemorySecrets(), clock: () => _now);
      st.store.setSetting('profile', {'weight_kg': 84, 'nutrition_mode': 'wissenschaft', 'goal': 'abnehmen'});
      st.store.section('hc_metrics')['2026-11-23'] = {'date': '2026-11-23', 'rest_kcal': 9, 'active_kcal': 5};
      st.store.setSetting('health_connect', true);
      final st2 = AppState(st.store, MemorySecrets(), health: _FakeHealth(const []), clock: () => _now);
      final t = st2.nutritionFor(st2.today)!;
      expect(t.fromBurn, isFalse);
      expect(t.kcal, greaterThan(1500));
      expect(t.carbsG, greaterThan(0));
      expect(t.hints.first, contains('unvollständig'));
    });

    test('Teilwerte aus Health Connect ergeben keine Ruhekalorien', () {
      final d = aggregateDaily([
        HcPoint('TOTAL_CALORIES_BURNED', 14, _t(23, 0), _t(23, 18), _zepp),
        HcPoint('ACTIVE_ENERGY_BURNED', 5, _t(23, 0), _t(23, 18), _zepp),
      ])['2026-11-23']!;
      expect(d.containsKey('rest_kcal'), isFalse);
    });
  });

  group('Sync mit Health Connect', () {
    test('ohne Garmin-Key, doppelte Trainings fallen weg', () async {
      final st = AppState(Store.memory(), MemorySecrets(), health: _FakeHealth(_points), clock: () => _now);
      expect(st.anySource, isFalse);
      expect(await st.connectHealthConnect(), isNull);
      expect(st.healthConnectOn, isTrue);
      expect(st.metricsFor('2026-11-23')!['steps'], 9000);
      // Garmin hat den Marsch auch, 2 Minuten früher gestartet
      st.store.section('activities')['gc-1'] = {
        'id': 'gc-1',
        'date': '2026-11-23',
        'start_time': '17:00',
        'kind': 'gehen',
        'source': 'garmin-personal-api'
      };
      final acts = st.activities(DateTime(2026, 11, 23), DateTime(2026, 11, 23));
      expect(acts.map((a) => a['id']), unorderedEquals(['gc-1', 'hc-w2']));
      expect(st.lastSync!['message'], contains('Amazfit'));
    });

    test('ohne Erlaubnis bleibt es aus', () async {
      final st =
          AppState(Store.memory(), MemorySecrets(), health: _FakeHealth(_points, granted: false), clock: () => _now);
      expect(await st.connectHealthConnect(), contains('Keine Erlaubnis'));
      expect(st.healthConnectOn, isFalse);
    });
  });
}
