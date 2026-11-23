/// Lokale Speicherung: alle Trainingsdaten als JSON-Datei im App-Ordner,
/// Schlüssel (Garmin, Anthropic) im sicheren Speicher von Android.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

const defaultSettings = <String, dynamic>{
  'goals': {'strength': 4, 'cardio': 3, 'march': 1},
  'max_hr': 190,
  'sleep_target_h': 8.0,
  // Freie Trainingsfenster je Wochentag (0 = Montag)
  'slots': {
    '0': [
      ['06:30', '07:45'],
      ['18:00', '19:30']
    ],
    '1': [
      ['06:30', '07:45'],
      ['18:00', '19:30']
    ],
    '2': [
      ['06:30', '07:45'],
      ['18:00', '19:30']
    ],
    '3': [
      ['06:30', '07:45'],
      ['18:00', '19:30']
    ],
    '4': [
      ['06:30', '07:45'],
      ['17:00', '18:30']
    ],
    '5': [
      ['08:00', '11:00'],
      ['16:00', '18:00']
    ],
    '6': [
      ['08:00', '11:00'],
      ['16:00', '18:00']
    ],
  },
  'preferences': 'Schwerpunkt Functional Fitness: Eigengewicht, Kettlebell, Gewichte. Ausdauer als '
      'Steigungsgehen auf dem Laufband. Märsche, auch mit Gewicht (Rucking), am Wochenende.',
  'constraints': 'Kniebeschwerden: wenig Laufen, keine Sprünge, keine tiefen Ausfallschritte.',
  'march_goal': 'Langer Marsch 25 km mit 12 kg Rucksack',
  'coach_model': 'claude-opus-5-5',
  'profile': {
    'sex': null,
    'height_cm': null,
    'birth_year': null,
    'weight_kg': null,
    'goal': 'halten',
    'nutrition_mode': 'wissenschaft',
  },
};

/// Datenablage. [save] schreibt verzögert, damit viele Änderungen nur einen Schreibvorgang kosten.
class Store {
  final File? file;
  Map<String, dynamic> data;
  Timer? _timer;

  Store._(this.file, this.data);

  factory Store.memory([Map<String, dynamic>? data]) => Store._(null, _withDefaults(data ?? {}));

  static Future<Store> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/echowp-trainer.json');
    var data = <String, dynamic>{};
    if (await f.exists()) {
      try {
        data = Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map);
      } catch (_) {
        // Beschädigte Datei sichern und neu beginnen
        await f.copy('${f.path}.defekt');
      }
    }
    return Store._(f, _withDefaults(data));
  }

  static Map<String, dynamic> _withDefaults(Map<String, dynamic> d) {
    for (final k in ['metrics', 'activities', 'journal', 'plans', 'briefings', 'chat', 'settings']) {
      d[k] = Map<String, dynamic>.from((d[k] as Map?) ?? {});
    }
    return d;
  }

  Map<String, dynamic> section(String name) => data[name] as Map<String, dynamic>;

  dynamic setting(String key) => section('settings').containsKey(key) ? section('settings')[key] : defaultSettings[key];

  Map<String, dynamic> get allSettings => {...defaultSettings, ...section('settings')};

  void setSetting(String key, dynamic value) {
    section('settings')[key] = value;
    save();
  }

  void save() {
    if (file == null) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 400), flush);
  }

  Future<void> flush() async {
    _timer?.cancel();
    if (file == null) return;
    final tmp = File('${file!.path}.tmp');
    await tmp.writeAsString(jsonEncode(data));
    await tmp.rename(file!.path);
  }

  String exportJson() => const JsonEncoder.withIndent(' ').convert(data);
}

/// Sicherer Speicher für Schlüssel und Tokens.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class DeviceSecrets implements SecretStore {
  static const _s = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String? value) =>
      value == null || value.isEmpty ? _s.delete(key: key) : _s.write(key: key, value: value);
}

class MemorySecrets implements SecretStore {
  final Map<String, String> values;
  MemorySecrets([Map<String, String>? v]) : values = v ?? {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String? value) async =>
      value == null || value.isEmpty ? values.remove(key) : values[key] = value;
}
