/// Health Connect (Android): Daten anderer Uhren, z. B. Amazfit (Zepp-App) und Suunto.
///
/// Zepp und Suunto haben keine offene Schnittstelle für Privatnutzer. Beide Apps schreiben
/// aber nach Health Connect, und dort liest die App mit Erlaubnis mit. Die Auswertung
/// (`aggregateDaily`, `workoutsToActivities`) ist reine Logik und ohne Handy testbar.
library;

import 'package:health/health.dart';

import '../logic/dates.dart';
import 'garmin.dart' show mapKind;

/// Ein Messwert, unabhängig vom Plugin (damit die Logik testbar bleibt).
class HcPoint {
  final String type; // STEPS, ACTIVE_ENERGY_BURNED, … (HealthDataType.name)
  final double value;
  final DateTime from, to;
  final String source; // Paketname der schreibenden App
  final String id;
  final String? workout; // Sportart bei WORKOUT
  final double? distanceM, kcal;

  const HcPoint(this.type, this.value, this.from, this.to, this.source,
      {this.id = '', this.workout, this.distanceM, this.kcal});
}

/// Lesbarer Name zur schreibenden App.
String sourceLabel(String pkg) {
  final p = pkg.toLowerCase();
  if (p.contains('huami') || p.contains('zepp') || p.contains('amazfit')) return 'Amazfit';
  if (p.contains('suunto') || p.startsWith('com.stt.')) return 'Suunto';
  if (p.contains('garmin')) return 'Garmin';
  if (p.contains('xiaomi') || p.contains('mi.health') || p.contains('mifitness')) return 'Xiaomi';
  if (p.contains('samsung')) return 'Samsung';
  if (p.contains('polar')) return 'Polar';
  if (p.contains('coros')) return 'Coros';
  if (p.contains('withings')) return 'Withings';
  if (p.contains('fitbit')) return 'Fitbit';
  if (p.contains('google')) return 'Google/Handy';
  return pkg;
}

/// Tageswerte aus allen Quellen. Summen (Schritte, Kalorien, Schlaf) werden je App gebildet,
/// genommen wird die App mit dem höchsten Wert. So zählt nichts doppelt, wenn zwei Apps
/// denselben Tag schreiben (z. B. Garmin Connect und Zepp).
Map<String, Map<String, dynamic>> aggregateDaily(List<HcPoint> points) {
  final sums = <String, Map<String, Map<String, double>>>{}; // Tag → Feld → Quelle → Summe
  final latest = <String, Map<String, (DateTime, double)>>{}; // Tag → Feld → letzter Wert
  final hrv = <String, List<double>>{};

  void add(String day, String field, String src, double v) {
    final bySrc = sums.putIfAbsent(day, () => {}).putIfAbsent(field, () => {});
    bySrc[src] = (bySrc[src] ?? 0) + v;
  }

  void last(String day, String field, DateTime t, double v) {
    final m = latest.putIfAbsent(day, () => {});
    final old = m[field];
    if (old == null || t.isAfter(old.$1)) m[field] = (t, v);
  }

  for (final p in points) {
    final day = iso(p.from);
    switch (p.type) {
      case 'STEPS':
        add(day, 'steps', p.source, p.value);
      case 'ACTIVE_ENERGY_BURNED':
        add(day, 'active_kcal', p.source, p.value);
      case 'TOTAL_CALORIES_BURNED':
        add(day, 'total_kcal', p.source, p.value);
      case 'SLEEP_SESSION':
        // Schlaf zählt für den Tag des Aufwachens
        add(iso(p.to), 'sleep_min', p.source, p.to.difference(p.from).inMinutes.toDouble());
      case 'BASAL_ENERGY_BURNED':
        last(day, 'rest_kcal', p.from, p.value); // Grundumsatz in kcal/Tag
      case 'RESTING_HEART_RATE':
        last(day, 'resting_hr', p.from, p.value);
      case 'HEART_RATE_VARIABILITY_RMSSD':
        hrv.putIfAbsent(day, () => []).add(p.value);
    }
  }

  final out = <String, Map<String, dynamic>>{};
  Map<String, dynamic> dayMap(String d) => out.putIfAbsent(d, () => {'date': d, 'source': 'health-connect'});

  sums.forEach((day, fields) {
    final m = dayMap(day);
    fields.forEach((field, bySrc) {
      final best = bySrc.entries.reduce((a, b) => b.value > a.value ? b : a);
      if (best.value <= 0) return;
      if (field == 'sleep_min') {
        m['sleep_hours'] = (best.value / 60 * 100).round() / 100;
        m['sleep_hours_src'] = sourceLabel(best.key);
      } else {
        m[field] = best.value.round();
        m['${field}_src'] = sourceLabel(best.key);
      }
    });
  });
  latest.forEach((day, fields) {
    final m = dayMap(day);
    fields.forEach((field, v) => m[field] = v.$2.round());
  });
  hrv.forEach((day, list) => dayMap(day)['hrv_ms'] = (list.reduce((a, b) => a + b) / list.length).round());

  // Ruhekalorien aus Gesamt minus Aktiv, falls keine App den Grundumsatz schreibt
  for (final m in out.values) {
    if (m['rest_kcal'] == null && m['total_kcal'] is num && m['active_kcal'] is num) {
      final rest = (m['total_kcal'] as num) - (m['active_kcal'] as num);
      if (rest > 0) m['rest_kcal'] = rest.round();
    }
  }
  return out;
}

/// Sportarten aus Health Connect auf die Arten der App abbilden.
const _hcKinds = {
  'weightlifting': 'kraft',
  'calisthenics': 'kraft',
  'high_intensity_interval_training': 'cardio',
  'biking': 'cardio',
  'biking_stationary': 'cardio',
  'rowing_machine': 'cardio',
  'stair_climbing_machine': 'cardio',
  'swimming_pool': 'cardio',
  'swimming_open_water': 'cardio',
  'running_treadmill': 'lauf',
  'guided_breathing': 'mobility',
};

String hcKind(String? type) {
  final t = (type ?? '').toLowerCase();
  return _hcKinds[t] ?? mapKind(t);
}

/// Trainings aus Health Connect als Aktivitäten (gleiches Format wie die Garmin-Aktivitäten).
List<Map<String, dynamic>> workoutsToActivities(List<HcPoint> points) => [
      for (final p in points)
        if (p.type == 'WORKOUT')
          {
            'id': 'hc-${p.id.isNotEmpty ? p.id : '${p.source}-${p.from.millisecondsSinceEpoch}'}',
            'date': iso(p.from),
            'start_time': hhmm(p.from),
            'kind': hcKind(p.workout),
            'type': (p.workout ?? 'other').toLowerCase(),
            'name': '${_workoutName(p.workout)} (${sourceLabel(p.source)})',
            'duration_s': p.to.difference(p.from).inSeconds.toDouble(),
            if (p.distanceM != null && p.distanceM! > 0) 'distance_m': p.distanceM,
            if (p.kcal != null && p.kcal! > 0) 'kcal': p.kcal,
            'source': 'health-connect',
            'device': sourceLabel(p.source),
          }
    ];

String _workoutName(String? t) => switch ((t ?? '').toUpperCase()) {
      'WALKING' => 'Gehen',
      'HIKING' => 'Wandern',
      'RUNNING' || 'RUNNING_TREADMILL' => 'Laufen',
      'STRENGTH_TRAINING' || 'WEIGHTLIFTING' => 'Krafttraining',
      'CALISTHENICS' => 'Eigengewicht',
      'HIGH_INTENSITY_INTERVAL_TRAINING' => 'HIIT',
      'BIKING' || 'BIKING_STATIONARY' => 'Radfahren',
      'ROWING' || 'ROWING_MACHINE' => 'Rudern',
      'SWIMMING_POOL' || 'SWIMMING_OPEN_WATER' => 'Schwimmen',
      'YOGA' => 'Yoga',
      'PILATES' => 'Pilates',
      'ELLIPTICAL' => 'Crosstrainer',
      'STAIR_CLIMBING' || 'STAIR_CLIMBING_MACHINE' => 'Treppensteigen',
      _ => 'Training',
    };

/// Gleiche Einheit doppelt (z. B. Garmin-API und Garmin Connect über Health Connect)?
/// Gilt als gleich, wenn Datum passt und der Start höchstens 10 Minuten auseinander liegt.
bool sameWorkout(Map a, Map b) {
  if (a['date'] != b['date']) return false;
  final x = minutesOf(a['start_time']), y = minutesOf(b['start_time']);
  if (x == null || y == null) return false;
  return (x - y).abs() <= 10;
}

int? minutesOf(dynamic hhmm) {
  if (hhmm is! String || hhmm.length < 5) return null;
  final h = int.tryParse(hhmm.substring(0, 2)), m = int.tryParse(hhmm.substring(3, 5));
  return h == null || m == null ? null : h * 60 + m;
}

/// Tageswerte zusammenführen: Garmin zuerst, Health Connect füllt Lücken.
/// Schritte und Kalorien: der höchste Wert gewinnt (andere Uhr am Handgelenk).
Map<String, dynamic>? mergeMetrics(Map<String, dynamic>? garmin, Map<String, dynamic>? hc) {
  if (hc == null) return garmin;
  if (garmin == null) return Map<String, dynamic>.from(hc);
  final m = Map<String, dynamic>.from(garmin);
  for (final e in hc.entries) {
    if (e.key == 'date' || e.key == 'source' || e.key.endsWith('_src')) continue;
    final g = m[e.key];
    final takeMax = const {'steps', 'active_kcal', 'total_kcal'}.contains(e.key);
    final useHc = g == null || (takeMax && e.value is num && g is num && (e.value as num) > g);
    if (useHc) {
      m[e.key] = e.value;
      if (hc['${e.key}_src'] != null) m['${e.key}_src'] = hc['${e.key}_src'];
    }
  }
  // Ruhe + Aktiv nach dem Zusammenführen stimmig halten
  if (m['rest_kcal'] is num && m['active_kcal'] is num) {
    final sum = (m['rest_kcal'] as num) + (m['active_kcal'] as num);
    if (m['total_kcal'] is! num || (m['total_kcal'] as num) < sum) m['total_kcal'] = sum.round();
  }
  return m;
}

// ---------------------------------------------------------------- Zugriff aufs Handy
const hcReadTypes = [
  HealthDataType.STEPS,
  HealthDataType.ACTIVE_ENERGY_BURNED,
  HealthDataType.TOTAL_CALORIES_BURNED,
  HealthDataType.BASAL_ENERGY_BURNED,
  HealthDataType.RESTING_HEART_RATE,
  HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
  HealthDataType.SLEEP_SESSION,
  HealthDataType.WORKOUT,
];

/// Für Trainings liest Health Connect auch die Strecke mit, dafür braucht es diese Erlaubnis.
const _authTypes = [...hcReadTypes, HealthDataType.DISTANCE_DELTA];

/// Schnittstelle, damit Tests ohne Handy laufen.
abstract class HealthReader {
  Future<bool> available();
  Future<void> install();
  Future<bool> authorize();
  Future<List<HcPoint>> read(DateTime start, DateTime end);
}

class HealthConnectSource implements HealthReader {
  final Health _health = Health();
  bool _configured = false;

  Future<void> _init() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Ist Health Connect auf dem Handy vorhanden?
  @override
  Future<bool> available() async {
    try {
      await _init();
      return await _health.isHealthConnectAvailable();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> install() async {
    await _init();
    await _health.installHealthConnect();
  }

  /// Fragt die Leserechte ab. Gibt true zurück, wenn der Nutzer zugestimmt hat.
  @override
  Future<bool> authorize() async {
    await _init();
    return _health.requestAuthorization(_authTypes, permissions: [for (final _ in _authTypes) HealthDataAccess.READ]);
  }

  @override
  Future<List<HcPoint>> read(DateTime start, DateTime end) async {
    await _init();
    final out = <HcPoint>[];
    for (final type in hcReadTypes) {
      // Einzeln lesen: fehlt eine Erlaubnis, gehen die anderen Werte trotzdem durch
      final List<HealthDataPoint> pts;
      try {
        pts = await _health.getHealthDataFromTypes(types: [type], startTime: start, endTime: end);
      } catch (_) {
        continue;
      }
      for (final p in pts) {
        final v = p.value;
        if (v is WorkoutHealthValue) {
          out.add(HcPoint(p.type.name, 0, p.dateFrom, p.dateTo, p.sourceName,
              id: p.uuid,
              workout: v.workoutActivityType.name,
              distanceM: v.totalDistance?.toDouble(),
              kcal: v.totalEnergyBurned?.toDouble()));
        } else if (v is NumericHealthValue) {
          out.add(HcPoint(p.type.name, v.numericValue.toDouble(), p.dateFrom, p.dateTo, p.sourceName, id: p.uuid));
        }
      }
    }
    return out;
  }
}
