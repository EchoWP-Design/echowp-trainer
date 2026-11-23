import 'package:echowp_trainer/logic/dates.dart';
import 'package:echowp_trainer/logic/endurance.dart';
import 'package:echowp_trainer/logic/nutrition.dart';
import 'package:echowp_trainer/logic/planner.dart';
import 'package:echowp_trainer/logic/readiness.dart';
import 'package:echowp_trainer/logic/streaks.dart';
import 'package:echowp_trainer/services/garmin.dart';
import 'package:echowp_trainer/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ernährung', () {
    test('Jans Formel entspricht der Excel-Tabelle (80 kg)', () {
      final t = calculateJan(80);
      expect(t.kcal, 2080);
      expect(t.proteinG, 160);
      expect(t.fatG, 69);
      expect(t.fiberG, 29);
      expect(t.carbsG, 204);
      expect(t.waterL, 2.7);
    });

    test('Mifflin-St Jeor und PAL', () {
      expect(mifflinStJeor(80, 180, 35, 'm'), closeTo(1755, 0.01));
      expect(mifflinStJeor(65, 168, 30, 'w'), closeTo(1389, 0.01));
      expect(palFromTraining(0), 1.4);
      expect(palFromTraining(4), 1.7);
      expect(palFromTraining(10), 2.0);
    });

    test('Wissenschaftsmodus im Defizit', () {
      final t =
          calculateScience(80, 180, 35, 'm', trainingHWeek: 6, goal: 'abnehmen', enduranceHWeek: 3, trainingHToday: 1);
      expect(t.proteinG, 176);
      expect(t.fiberG, greaterThanOrEqualTo(30));
      expect(t.fatG, greaterThanOrEqualTo(64));
      expect(t.waterL, closeTo(3.55, 0.1));
      expect((t.proteinPct + t.fatPct + t.carbsPct - 100).abs(), lessThanOrEqualTo(2));
      expect(t.hints.any((h) => h.contains('Defizit')), isTrue);
    });

    test('ohne Profil fällt der Rechner auf Jans Formel zurück', () {
      final t = calculateNutrition(80, {'nutrition_mode': 'wissenschaft'}, {});
      expect(t.mode, 'jan');
      expect(t.hints, isNotEmpty);
    });

    test('ungültiges Gewicht', () => expect(() => calculateJan(0), throwsArgumentError));
  });

  group('Bereitschaft', () {
    final history = [
      for (var i = 0; i < 7; i++) {'hrv_ms': 50, 'resting_hr': 50}
    ];

    test('gute Werte ergeben Push Day', () {
      final r = computeReadiness(
          {'sleep_hours': 8.2, 'sleep_score': 90, 'hrv_ms': 55, 'resting_hr': 48, 'body_battery': 95},
          {'mood': 9, 'energy': 9, 'motivation': 9, 'soreness': 2, 'stress': 2},
          history);
      expect(r.level, 'push');
      expect(r.score, greaterThanOrEqualTo(80));
    });

    test('schlechtes Gefühl deckelt den Score', () {
      final r = computeReadiness(
          {'sleep_hours': 8, 'sleep_score': 90, 'hrv_ms': 55, 'resting_hr': 48, 'body_battery': 100},
          {'mood': 2, 'energy': 1, 'motivation': 2, 'soreness': 9, 'stress': 9},
          history);
      expect(r.score, lessThan(40));
      expect(r.notes.first, contains('Gefühl'));
    });

    test('Werte wie am 23.11. ergeben Recovery', () {
      final r = computeReadiness(
          {'sleep_hours': 3.9, 'sleep_score': 39, 'hrv_ms': 36, 'resting_hr': 55, 'body_battery': 32}, null, history);
      expect(r.level, 'recovery');
    });

    test('ohne Daten unbekannt', () => expect(computeReadiness(null, null, []).score, isNull));

    test('Korrekturen aus dem Journal gelten', () {
      final r = computeReadiness({
        'sleep_hours': 3.0
      }, {
        'corrections': {'sleep_hours': 8.0}
      }, []);
      expect(r.components['sleep'], 100);
    });
  });

  group('Wochenplan', () {
    final settings = Map<String, dynamic>.from(defaultSettings);

    test('knieschonend: kein Laufen, Marsch am Wochenende, Ziele erfüllt', () {
      final ws = DateTime(2026, 11, 30); // KW 49, Aufbau
      final p = buildWeek(ws, settings, avgReadiness: 75);
      expect(p.phase, 'Aufbau');
      expect(p.sessions.where((s) => s.kind == 'kraft').length, 4);
      expect(p.sessions.where((s) => s.kind == 'cardio' || s.kind == 'intervall').length, 3);
      final march = p.sessions.singleWhere((s) => s.kind == 'marsch');
      expect(parseIso(march.date).weekday, DateTime.sunday);
      final text = p.sessions.map((s) => '${s.title} ${s.focus} ${s.exercises}').join(' ').toLowerCase();
      expect(text, isNot(contains('lauf ')));
      expect(text, isNot(contains('sprung ')));
      expect(text, isNot(contains('box jump')));
      expect(p.unplaced, isEmpty);
    });

    test('Deload in jeder vierten Woche, Entlastung bei niedrigem Score', () {
      expect(determinePhase(DateTime(2026, 11, 23), 80).$1, 'Deload'); // KW 48
      expect(determinePhase(DateTime(2026, 11, 30), 50).$1, 'Entlastung');
    });

    test('Plan übersteht JSON', () {
      final p = buildWeek(DateTime(2026, 11, 30), settings);
      final back = WeekPlan.fromJson(p.toJson());
      expect(back.sessions.length, p.sessions.length);
      expect(back.sessions.first.exercises, p.sessions.first.exercises);
    });
  });

  group('Datum', () {
    test('ISO-Woche', () {
      expect(isoWeek(DateTime(2026, 11, 23)), 48);
      expect(isoWeek(DateTime(2027, 1, 1)), 53);
      expect(isoWeek(DateTime(2026, 1, 1)), 1);
    });
    test('Wochenstart Montag', () => expect(iso(weekStartOf(DateTime(2026, 11, 29))), '2026-11-23'));
    test('Tage über Zeitumstellung', () => expect(iso(addDays(DateTime(2026, 3, 28), 1)), '2026-03-29'));
  });

  group('Streaks und Märsche', () {
    test('offener heutiger Tag bricht keinen Streak', () {
      expect(streakOf([true, true, true, false]), 3);
      expect(streakOf([true, false, true, true]), 2);
    });

    test('Langer Marsch zählt ab 60 Minuten Gehen', () {
      final g = weekGoals([
        {'kind': 'gehen', 'duration_s': 4000},
        {'kind': 'gehen', 'duration_s': 1800},
        {'kind': 'kraft', 'duration_s': 3600},
      ], {
        'strength': 4,
        'cardio': 3,
        'march': 1
      });
      expect(g[0].done, 1);
      expect(g[2].done, 1);
    });

    test('Marsch-Statistik', () {
      final s = marchStats([
        {'duration_s': 7200, 'distance_m': 12000},
        {'duration_s': 600, 'distance_m': 1000},
      ]);
      expect(s.count, 1);
      expect(s.longestKm, 12.0);
      expect(s.avgPace, '10:00 /km');
    });
  });

  group('Garmin-Zuordnung', () {
    test('verschachtelte Werte', () {
      expect(
          findValue({
            'a': [
              {
                'b': {'restingHeartRate': 49}
              }
            ]
          }, [
            'restingHeartRate'
          ]),
          49);
      expect(
          findValue({
            'x': {
              'overall': {'value': 81}
            }
          }, [
            'overall'
          ]),
          81);
    });

    test('echte Antwortstruktur der Personal API', () {
      final summary = {
        'data': [
          {
            'calendarDate': '2026-11-22',
            'movement': {
              'steps': {'goal': 8000, 'value': 4321}
            },
            'heartRate': {'minValue': 45, 'maxValue': 120, 'restingValue': 52},
            'stress': {'avgLevel': 31, 'maxLevel': 90},
            'bodyBattery': {'minValue': 20, 'maxValue': 95, 'latestValue': 30},
          }
        ]
      };
      final bb = [
        {
          'date': '2026-11-22',
          'bodyBatteryValuesArray': [
            [1000000, 40],
            [5000000, 88],
            [9000000, 70]
          ]
        }
      ];
      final sleep = {
        'sleepTimeSeconds': 28800,
        'sleepEndTimestampGMT': 5000000,
        'sleepScores': {
          'overall': {'value': 80}
        }
      };
      final m = parseDaily(
          '2026-11-22',
          sleep,
          {
            'hrvSummary': {'lastNightAvg': 50}
          },
          summary,
          bb);
      expect(m['steps'], 4321);
      expect(m['resting_hr'], 52);
      expect(m['stress_avg'], 31);
      expect(m['body_battery'], 88);
      expect(m['sleep_hours'], 8.0);
      expect(m['sleep_score'], 80);
      expect(m['hrv_ms'], 50);
    });

    test('ältere Antwortstruktur', () {
      final m = parseDaily('2026-11-22', {
        'dailySleepDTO': {
          'sleepTimeSeconds': 25200,
          'sleepScores': {
            'overall': {'value': 77}
          }
        }
      }, {
        'hrvSummary': {'lastNightAvg': 61}
      }, [
        {'calendarDate': '2026-11-21', 'restingHeartRate': 60},
        {'calendarDate': '2026-11-22', 'restingHeartRate': 50, 'totalSteps': 8000, 'averageStressLevel': 25},
      ], [
        {'calendarDate': '2026-11-22', 'highestValue': 88}
      ]);
      expect([m['sleep_hours'], m['sleep_score'], m['hrv_ms'], m['resting_hr'], m['steps'], m['body_battery']],
          [7.0, 77, 61, 50, 8000, 88]);
    });

    test('Aktivitätsarten', () {
      expect(mapKind('rucking'), 'gehen');
      expect(mapKind('kettlebell'), 'kraft');
      expect(mapKind('treadmill_running'), 'lauf');
      expect(mapKind(null), 'sonstiges');
      final a = parseActivity({
        'activityId': 1,
        'startTimeLocal': '2026-07-12 08:15:00',
        'activityType': {'typeKey': 'hiking'},
        'duration': 5400.0,
        'distance': 9000.0,
        'averageHR': 120,
      });
      expect(a['kind'], 'gehen');
      expect(a['date'], '2026-07-12');
      expect(a['start_time'], '08:15');
    });
  });
}
