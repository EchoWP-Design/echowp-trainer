/// Offizielle Garmin Connect Personal API, direkt vom Handy aus.
///
/// Der Personal API Key (connect.garmin.com/app/settings/personalApiToken)
/// wird gegen ein Zugriffstoken (24 h) getauscht. Damit liest die App Schlaf,
/// HRV, Tageswerte, Body Battery und Aktivitäten. Die Feldzuordnung ist an
/// echten Antworten geprüft (siehe docs/GARMIN.md).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../logic/dates.dart';

const garminBaseUrl = 'https://personal.connectapi.garmin.com';
const _tokenPath = '/personalapitoken-service/personal-api/personal-api-key/token';

class GarminError implements Exception {
  final String message;
  GarminError(this.message);
  @override
  String toString() => message;
}

// ---------------------------------------------------------------- Zuordnung
const _kindMap = {
  'running': 'lauf',
  'trail_running': 'lauf',
  'treadmill_running': 'lauf',
  'track_running': 'lauf',
  'street_running': 'lauf',
  'strength_training': 'kraft',
  'training': 'kraft',
  'kettlebell': 'kraft',
  'functional_training': 'kraft',
  'cycling': 'cardio',
  'indoor_cycling': 'cardio',
  'road_biking': 'cardio',
  'mountain_biking': 'cardio',
  'virtual_ride': 'cardio',
  'lap_swimming': 'cardio',
  'open_water_swimming': 'cardio',
  'swimming': 'cardio',
  'rowing': 'cardio',
  'indoor_rowing': 'cardio',
  'elliptical': 'cardio',
  'hiit': 'cardio',
  'cardio': 'cardio',
  'stair_climbing': 'cardio',
  'yoga': 'mobility',
  'pilates': 'mobility',
  'flexibility_training': 'mobility',
  'breathwork': 'mobility',
  'walking': 'gehen',
  'hiking': 'gehen',
  'rucking': 'gehen',
  'treadmill_walking': 'gehen',
  'indoor_walking': 'gehen',
};

String mapKind(String? garminType) => _kindMap[(garminType ?? '').toLowerCase()] ?? 'sonstiges';

/// Sucht rekursiv den ersten Zahlenwert unter einem der Schlüssel.
double? findValue(dynamic data, List<String> keys) {
  if (data is Map) {
    for (final k in keys) {
      final v = data[k];
      if (v is num) return v.toDouble();
      if (v is Map && v['value'] is num) return (v['value'] as num).toDouble();
    }
    for (final v in data.values) {
      final f = findValue(v, keys);
      if (f != null) return f;
    }
  } else if (data is List) {
    for (final item in data) {
      final f = findValue(item, keys);
      if (f != null) return f;
    }
  }
  return null;
}

Map? findMap(dynamic data, String key) {
  if (data is Map) {
    if (data[key] is Map) return data[key] as Map;
    for (final v in data.values) {
      final r = findMap(v, key);
      if (r != null) return r;
    }
  } else if (data is List) {
    for (final v in data) {
      final r = findMap(v, key);
      if (r != null) return r;
    }
  }
  return null;
}

/// Aus Listen-Antworten den Eintrag für einen Kalendertag wählen.
dynamic pickDay(dynamic data, String day) {
  if (data is Map) {
    for (final key in ['dailySummaries', 'summaries', 'values', 'data', 'items']) {
      if (data[key] is List) return pickDay(data[key], day);
    }
    return data;
  }
  if (data is List) {
    for (final item in data) {
      if (item is Map) {
        final d = (item['calendarDate'] ?? item['date'] ?? '').toString();
        if (d.length >= 10 && d.substring(0, 10) == day) return item;
      }
    }
    return null;
  }
  return data;
}

/// Body Battery zum Aufwachzeitpunkt aus bodyBatteryValuesArray [[ms, Wert], ...].
double? bodyBatteryAt(dynamic bb, double? tsMs) {
  if (bb is! Map || tsMs == null) return null;
  final values = [
    for (final v in (bb['bodyBatteryValuesArray'] as List?) ?? [])
      if (v is List && v.length >= 2 && v[0] is num && v[1] is num) [(v[0] as num).toDouble(), (v[1] as num).toDouble()]
  ];
  if (values.isEmpty) return null;
  final limit = tsMs + 30 * 60 * 1000;
  final before = values.where((v) => v[0] <= limit).toList();
  if (before.isNotEmpty) {
    before.sort((a, b) => a[0].compareTo(b[0]));
    return before.last[1];
  }
  values.sort((a, b) => (a[0] - tsMs).abs().compareTo((b[0] - tsMs).abs()));
  return values.first[1];
}

Map<String, dynamic> parseDaily(String day, dynamic sleep, dynamic hrv, dynamic summary, dynamic bodyBattery) {
  final m = <String, dynamic>{'date': day, 'source': 'garmin-personal-api'};
  final secs = findValue(sleep, ['sleepTimeSeconds']);
  if (secs != null && secs > 0) m['sleep_hours'] = (secs / 36).round() / 100;
  m['sleep_score'] = findValue(findMap(sleep, 'sleepScores') ?? sleep, ['overall', 'overallScore', 'sleepScore']);
  m['hrv_ms'] = findValue(hrv, ['lastNightAvg', 'lastNightAverage']);
  final s = pickDay(summary, day);
  m['resting_hr'] = findValue(s, ['restingHeartRate', 'restingHeartRateValue', 'restingValue']);
  final stress = findValue(s is Map ? s['stress'] : null, ['avgLevel']) ??
      findValue(s, ['averageStressLevel', 'avgStressLevel', 'overallStressLevel']);
  m['stress_avg'] = (stress != null && stress >= 0) ? stress : null;
  m['steps'] = findValue(s, ['totalSteps', 'steps'])?.toInt();
  final bb = pickDay(bodyBattery, day);
  final wake = findValue(sleep, ['sleepEndTimestampGMT']);
  m['body_battery'] = bodyBatteryAt(bb, wake) ??
      findValue(s is Map ? s['bodyBattery'] : null, ['maxValue']) ??
      findValue(bb, ['bodyBatteryAtWakeTime', 'atWakeTime', 'startOfDayValue', 'highestValue', 'maxValue']);
  m.removeWhere((k, v) => v == null);
  return m;
}

bool hasMetricData(Map<String, dynamic> m) => m.keys.any((k) => k != 'date' && k != 'source');

double? _num(dynamic v) => v is num ? v.toDouble() : null;

Map<String, dynamic> parseActivity(Map raw) {
  final start = (raw['startTimeLocal'] ?? '').toString();
  final type = raw['activityType'] is Map ? (raw['activityType'] as Map)['typeKey'] as String? : null;
  final a = <String, dynamic>{
    'id': 'gc-${raw['activityId']}',
    'date': start.length >= 10 ? start.substring(0, 10) : '',
    'start_time': start.length >= 16 ? start.substring(11, 16) : null,
    'kind': mapKind(type),
    'type': type,
    'name': (raw['activityName'] ?? '').toString(),
    'duration_s': _num(raw['duration']),
    'distance_m': _num(raw['distance']),
    'avg_hr': _num(raw['averageHR']),
    'max_hr': _num(raw['maxHR']),
    'training_load': _num(raw['activityTrainingLoad']),
    'source': 'garmin-personal-api',
  };
  a.removeWhere((k, v) => v == null);
  return a;
}

double _jwtExp(String token) {
  try {
    var payload = token.split('.')[1];
    payload += '=' * ((4 - payload.length % 4) % 4);
    final data = jsonDecode(utf8.decode(base64Url.decode(payload))) as Map;
    return (data['exp'] as num).toDouble();
  } catch (_) {
    return DateTime.now().millisecondsSinceEpoch / 1000 + 23 * 3600;
  }
}

// ---------------------------------------------------------------- Client
class GarminClient {
  final String apiKey;
  final http.Client http_;
  final String baseUrl;

  /// Gespeichertes Token laden/sichern (sicherer Speicher des Handys).
  final Future<Map<String, dynamic>?> Function() loadToken;
  final Future<void> Function(Map<String, dynamic>) saveToken;

  String? _token;
  double _exp = 0;
  Future<String>? _pending;

  GarminClient(this.apiKey,
      {http.Client? client, this.baseUrl = garminBaseUrl, required this.loadToken, required this.saveToken})
      : http_ = client ?? http.Client();

  String get _keyTail => apiKey.length > 6 ? apiKey.substring(apiKey.length - 6) : apiKey;

  /// Parallele Abfragen teilen sich einen laufenden Token-Abruf.
  Future<String> token({bool force = false}) {
    final p = _pending;
    if (p != null) return p;
    final f = _token_(force).whenComplete(() => _pending = null);
    _pending = f;
    return f;
  }

  Future<String> _token_(bool force) async {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    if (!force && _token == null) {
      final c = await loadToken();
      if (c != null && c['key_tail'] == _keyTail) {
        _token = c['access_token'] as String?;
        _exp = (c['expires_at'] as num?)?.toDouble() ?? 0;
      }
    }
    if (!force && _token != null && _exp - now > 3600) return _token!;
    final http.Response resp;
    try {
      resp = await http_.post(Uri.parse('$baseUrl$_tokenPath'),
          headers: {'Accept': '*/*', 'Authorization': 'ApiKey ${apiKey.trim()}'}).timeout(const Duration(seconds: 30));
    } catch (e) {
      throw GarminError('Garmin nicht erreichbar. Internetverbindung prüfen.');
    }
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw GarminError('Garmin hat den Personal API Key abgelehnt (abgelaufen oder gelöscht?). '
          'Neuen Key unter connect.garmin.com/app/settings/personalApiToken erstellen.');
    }
    if (resp.statusCode != 200) throw GarminError('Garmin-Token konnte nicht geholt werden (HTTP ${resp.statusCode}).');
    _token = resp.body.trim();
    _exp = _jwtExp(_token!);
    await saveToken({'access_token': _token, 'expires_at': _exp, 'key_tail': _keyTail});
    return _token!;
  }

  Future<dynamic> get(String path, [Map<String, String>? params, bool retry = true]) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: params);
    final http.Response resp;
    try {
      resp = await http_.get(uri, headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${await token()}',
      }).timeout(const Duration(seconds: 30));
    } on GarminError {
      rethrow;
    } catch (e) {
      throw GarminError('Garmin nicht erreichbar. Internetverbindung prüfen.');
    }
    if (resp.statusCode == 401 && retry) {
      await token(force: true);
      return get(path, params, false);
    }
    if (resp.statusCode == 204 || resp.statusCode == 404) return null;
    if (resp.statusCode != 200) throw GarminError('Garmin-Abfrage fehlgeschlagen (HTTP ${resp.statusCode}).');
    if (resp.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  /// Einzelabfrage, die bei kleinen Fehlern (z. B. fehlende Daten) null liefert.
  Future<dynamic> _safe(String path, [Map<String, String>? params]) async {
    try {
      return await get(path, params);
    } on GarminError catch (e) {
      if (e.message.contains('abgelehnt') || e.message.contains('nicht erreichbar')) rethrow;
      return null;
    }
  }

  Future<Map<String, dynamic>> rawDay(String day) async {
    final r = await Future.wait([
      _safe('/sleep-service/sleep/dailySleep', {'date': day}),
      _safe('/hrv-service/hrv/$day'),
      _safe('/usersummary-service/v2/dailysummaries', {'startDate': day, 'endDate': day}),
      _safe('/wellness-service/wellness/bodyBattery/reports/daily', {'startDate': day, 'endDate': day}),
    ]);
    return {'sleep': r[0], 'hrv': r[1], 'summary': r[2], 'body_battery': r[3]};
  }

  Future<Map<String, dynamic>> fetchDaily(DateTime day) async {
    final d = iso(day);
    final raw = await rawDay(d);
    return parseDaily(d, raw['sleep'], raw['hrv'], raw['summary'], raw['body_battery']);
  }

  Future<List<Map<String, dynamic>>> fetchActivities(DateTime start, DateTime end) async {
    final out = <Map<String, dynamic>>[];
    for (var offset = 0; offset <= 500; offset += 50) {
      final page = await _safe('/activitylist-service/activities/search/activities', {
        'start': '$offset',
        'limit': '50',
        'startDate': iso(start),
        'endDate': iso(end),
      });
      final items = page is List ? page : ((page is Map ? page['activityList'] : null) as List? ?? []);
      out.addAll([
        for (final a in items)
          if (a is Map && a['activityId'] != null) parseActivity(a)
      ]);
      if (items.length < 50) break;
    }
    return out;
  }
}
