/// Fachlogik der App: Daten, Sync, Score, Planung, Coach.
library;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'logic/dates.dart';
import 'logic/disciplines.dart';
import 'logic/endurance.dart';
import 'logic/food.dart';
import 'logic/nutrition.dart';
import 'logic/planner.dart';
import 'logic/readiness.dart';
import 'logic/streaks.dart';
import 'services/coach.dart';
import 'services/food_lookup.dart';
import 'services/garmin.dart';
import 'services/health_connect.dart';
import 'services/storage.dart';
import 'services/updater.dart';

const _kindWeight = {'kraft': 1.0, 'cardio': 1.0, 'intervall': 1.0, 'lauf': 1.0, 'gehen': 0.8, 'mobility': 0.3};

class AppState extends ChangeNotifier {
  final Store store;
  final SecretStore secrets;
  final http.Client? httpClient;
  final HealthReader? health;
  DateTime Function() clock;

  String? garminKey;
  String? anthropicKey;
  bool busy = false;
  String? busyLabel;
  String? lastError;

  AppState(this.store, this.secrets, {this.httpClient, this.health, DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  DateTime get today => dayOnly(clock());

  Future<void> init() async {
    migrateSettings();
    garminKey = await secrets.read('garmin_key');
    anthropicKey = await secrets.read('anthropic_key');
    notifyListeners();
  }

  bool get garminConfigured => (garminKey ?? '').isNotEmpty;
  bool get healthConnectOn => health != null && store.setting('health_connect') == true;
  bool get anySource => garminConfigured || healthConnectOn;
  bool get coachEnabled => (anthropicKey ?? '').isNotEmpty;
  String get coachModel => (store.setting('coach_model') as String?) ?? defaultCoachModel;

  Future<void> setKeys({String? garmin, String? anthropic}) async {
    if (garmin != null) {
      garminKey = garmin.trim();
      await secrets.write('garmin_key', garminKey);
      await secrets.write('garmin_token', null);
    }
    if (anthropic != null) {
      anthropicKey = anthropic.trim();
      await secrets.write('anthropic_key', anthropicKey);
    }
    notifyListeners();
  }

  GarminClient _garmin() => GarminClient(garminKey!,
      client: httpClient,
      loadToken: () async {
        final raw = await secrets.read('garmin_token');
        if (raw == null) return null;
        final p = raw.split('|');
        return p.length == 3 ? {'access_token': p[0], 'expires_at': double.tryParse(p[1]), 'key_tail': p[2]} : null;
      },
      saveToken: (t) => secrets.write('garmin_token', '${t['access_token']}|${t['expires_at']}|${t['key_tail']}'));

  CoachClient? get _coach => coachEnabled ? CoachClient(anthropicKey!, model: coachModel, client: httpClient) : null;

  Future<T?> _run<T>(String label, Future<T> Function() fn) async {
    busy = true;
    busyLabel = label;
    lastError = null;
    notifyListeners();
    try {
      return await fn();
    } catch (e) {
      lastError = e.toString();
      return null;
    } finally {
      busy = false;
      busyLabel = null;
      notifyListeners();
    }
  }

  /// Bis 1.2: feste Ziele (Kraft, Steigung, Marsch) und Jans Vorgaben als Standard.
  /// Bestehende Installationen behalten genau das, neue starten neutral.
  void migrateSettings() {
    final s = store.section('settings');
    if (s.containsKey('disciplines')) return;
    final used = ['metrics', 'activities', 'journal', 'plans', 'food'].any((k) => store.section(k).isNotEmpty);
    if (!used) {
      // Neue Installation: neutrale Auswahl fest speichern, damit später nichts mehr umgestellt wird
      s['disciplines'] = [for (final g in disciplinesFrom(defaultSettings)) g.toJson()];
      store.save();
      return;
    }
    final goals = (s['goals'] as Map?) ?? const {'strength': 4, 'cardio': 3, 'march': 1};
    s['disciplines'] = [for (final g in legacyDisciplines(goals)) g.toJson()];
    s['knee_friendly'] = true;
    s.putIfAbsent(
        'preferences',
        () => 'Schwerpunkt Functional Fitness: Eigengewicht, Kettlebell, Gewichte. Ausdauer als '
            'Steigungsgehen auf dem Laufband. Märsche, auch mit Gewicht (Rucking), am Wochenende.');
    s.putIfAbsent('constraints', () => 'Kniebeschwerden: wenig Laufen, keine Sprünge, keine tiefen Ausfallschritte.');
    s.putIfAbsent('march_goal', () => 'Langer Marsch 25 km mit 12 kg Rucksack');
    store.save();
  }

  List<DisciplineGoal> get disciplines => disciplinesFrom(store.allSettings);

  void setDisciplines(List<DisciplineGoal> list) {
    store.setSetting('disciplines', [for (final g in list.take(maxDisciplines)) g.toJson()]);
    notifyListeners();
  }

  // ---------------------------------------------------------------- Updates
  ReleaseInfo? update;
  String? updateError;
  bool updateChecking = false;

  bool get showUpdateBanner => update != null && store.setting('update_dismissed') != update!.tag;

  /// Prüft auf eine neue App-Version. Automatisch höchstens einmal am Tag.
  Future<void> checkForUpdate({bool manual = false}) async {
    if (!manual && store.setting('update_checked') == iso(today)) return;
    updateChecking = true;
    updateError = null;
    notifyListeners();
    try {
      final r = await Updater(client: httpClient).latest();
      update = r != null && Updater.isNewer(r) ? r : null;
      store.setSetting('update_checked', iso(today));
      if (manual && update != null) store.section('settings').remove('update_dismissed');
    } catch (e) {
      if (manual) updateError = e.toString();
    } finally {
      updateChecking = false;
      notifyListeners();
    }
  }

  void dismissUpdate() {
    if (update != null) store.setSetting('update_dismissed', update!.tag);
    notifyListeners();
  }

  // ---------------------------------------------------------------- Daten
  /// Tageswerte: Garmin zuerst, andere Uhren (Health Connect) füllen Lücken.
  Map<String, dynamic>? metricsFor(String d) => mergeMetrics(
      (store.section('metrics')[d] as Map?)?.cast<String, dynamic>(),
      healthConnectOn ? (store.section('hc_metrics')[d] as Map?)?.cast<String, dynamic>() : null);
  Map<String, dynamic>? journalFor(String d) => (store.section('journal')[d] as Map?)?.cast<String, dynamic>();

  Map<String, Map<String, dynamic>> _range(String section, DateTime start, DateTime end) {
    final s = iso(start), e = iso(end);
    return {
      for (final entry in store.section(section).entries)
        if (entry.key.compareTo(s) >= 0 && entry.key.compareTo(e) <= 0)
          entry.key: (entry.value as Map).cast<String, dynamic>()
    };
  }

  List<Map<String, dynamic>> activities(DateTime start, DateTime end) {
    final s = iso(start), e = iso(end);
    final all = [
      for (final a in store.section('activities').values)
        if ((a['date'] as String).compareTo(s) >= 0 && (a['date'] as String).compareTo(e) <= 0)
          (a as Map).cast<String, dynamic>()
    ];
    // Einheiten aus Health Connect nur, wenn sie nicht schon von Garmin (oder einer
    // anderen App) für dieselbe Zeit vorliegen
    final list = [
      for (final a in all)
        if (a['source'] != 'health-connect') a
    ];
    if (healthConnectOn) {
      for (final a in all) {
        if (a['source'] == 'health-connect' && !list.any((b) => sameWorkout(a, b))) list.add(a);
      }
    }
    list.sort((a, b) => '${b['date']}${b['start_time'] ?? ''}'.compareTo('${a['date']}${a['start_time'] ?? ''}'));
    return list;
  }

  // ---------------------------------------------------------------- Sync
  Map<String, dynamic>? get lastSync => (store.data['last_sync'] as Map?)?.cast<String, dynamic>();

  bool get syncDue {
    final ts = lastSync?['ts'] as String?;
    if (ts == null) return true;
    return clock().difference(DateTime.parse(ts)).inMinutes >= 60;
  }

  Future<String?> sync({int days = 3, int activityDays = 14}) async {
    if (!anySource) {
      lastError = 'Erst unter „Daten“ den Garmin Personal API Key eintragen oder Health Connect verbinden.';
      notifyListeners();
      return null;
    }
    return _run('Daten werden synchronisiert …', () async {
      final parts = <String>[];
      final errors = <String>[];
      if (garminConfigured) {
        try {
          parts.add(await _syncGarmin(days, activityDays));
        } catch (e) {
          errors.add('Garmin: $e');
        }
      }
      if (healthConnectOn) {
        try {
          parts.add(await _syncHealthConnect(activityDays));
        } catch (e) {
          errors.add('Health Connect: $e');
        }
      }
      final msg = [...parts, ...errors].join(' · ');
      store.data['last_sync'] = {'ts': clock().toIso8601String(), 'ok': errors.isEmpty, 'message': msg};
      store.save();
      if (parts.isEmpty) throw Exception(errors.join(' · '));
      return msg;
    });
  }

  void _storeActivity(Map<String, dynamic> a) {
    final stored = store.section('activities');
    final old = (stored[a['id']] as Map?) ?? {};
    stored[a['id'] as String] = {
      ...a,
      if (old['rpe'] != null) 'rpe': old['rpe'],
      if (old['feedback'] != null) 'feedback': old['feedback']
    };
  }

  Future<String> _syncGarmin(int days, int activityDays) async {
    final g = _garmin();
    var nDays = 0;
    for (var i = days - 1; i >= 0; i--) {
      final m = await g.fetchDaily(addDays(today, -i));
      if (hasMetricData(m)) {
        store.section('metrics')[m['date'] as String] = m;
        nDays++;
      }
    }
    final acts = await g.fetchActivities(addDays(today, -(activityDays - 1)), today);
    acts.forEach(_storeActivity);
    return 'Garmin: $nDays Tage, ${acts.length} Aktivitäten';
  }

  /// Liest Werte anderer Uhren (Amazfit/Zepp, Suunto, …) aus Health Connect.
  Future<String> _syncHealthConnect(int days) async {
    final pts = await health!.read(addDays(today, -(days - 1)), clock());
    final daily = aggregateDaily(pts);
    final section = store.section('hc_metrics');
    daily.forEach((d, m) => section[d] = m);
    final acts = workoutsToActivities(pts);
    acts.forEach(_storeActivity);
    final devices = {for (final p in pts) sourceLabel(p.source)}.toList()..sort();
    return 'Health Connect: ${daily.length} Tage, ${acts.length} Trainings'
        '${devices.isEmpty ? '' : ' (${devices.join(', ')})'}';
  }

  /// Health Connect einrichten: Erlaubnis holen, einschalten, gleich synchronisieren.
  Future<String?> connectHealthConnect() async {
    final h = health;
    if (h == null) return 'Health Connect gibt es nur auf Android.';
    if (!await h.available()) {
      await h.install();
      return 'Health Connect ist nicht installiert. Bitte aus dem Play Store installieren und erneut verbinden.';
    }
    final ok = await h.authorize();
    if (!ok) return 'Keine Erlaubnis erteilt. In Health Connect unter App-Berechtigungen „EchoWP Trainer“ freigeben.';
    store.setSetting('health_connect', true);
    notifyListeners();
    await sync();
    return null;
  }

  void disconnectHealthConnect() {
    store.setSetting('health_connect', false);
    notifyListeners();
  }

  // ---------------------------------------------------------------- Score
  Readiness readinessFor(DateTime d) {
    final day = iso(d);
    final history = [
      for (var i = 1; i <= 7; i++)
        if (metricsFor(iso(addDays(d, -i))) case final m?) m
    ];
    final target = (store.setting('sleep_target_h') as num?)?.toDouble() ?? 8.0;
    return computeReadiness(metricsFor(day), journalFor(day), history, sleepTarget: target);
  }

  List<(String, int?)> readinessTrend(DateTime end, {int days = 14}) =>
      [for (var i = days - 1; i >= 0; i--) (iso(addDays(end, -i)), readinessFor(addDays(end, -i)).score)];

  double? avgReadiness(DateTime end, {int days = 7}) {
    final s = [
      for (final p in readinessTrend(end, days: days))
        if (p.$2 != null) p.$2!
    ];
    return s.isEmpty ? null : s.reduce((a, b) => a + b) / s.length;
  }

  // ---------------------------------------------------------------- Plan
  WeekPlan? planFor(DateTime weekStart) {
    final raw = store.section('plans')[iso(weekStart)];
    return raw == null ? null : WeekPlan.fromJson((raw as Map).cast<String, dynamic>());
  }

  List<PlannedSession> sessionsOn(DateTime d) =>
      (planFor(weekStartOf(d))?.sessions ?? []).where((s) => s.date == iso(d)).toList();

  (int, int) get zone2 => zone2Range((store.setting('max_hr') as num?) ?? 190);

  Future<WeekPlan?> planWeek(DateTime weekStart, {String? instruction}) {
    return _run(coachEnabled ? 'Coach plant die Woche …' : 'Woche wird geplant …', () async {
      final base = buildWeek(weekStart, store.allSettings, avgReadiness: avgReadiness(today), zone2Hr: zone2);
      var plan = base;
      final coach = _coach;
      String? warn;
      if (coach != null) {
        final ctx = context(today, days: 30);
        ctx['aktueller_plan'] = planFor(weekStart)?.toJson();
        try {
          plan = await coach.planWeek(ctx, base, instruction: instruction);
        } catch (e) {
          warn = e.toString();
        }
      }
      // Erledigte/ausgelassene Einheiten bleiben erhalten
      final old = planFor(weekStart);
      final kept = (old?.sessions ?? []).where((s) => s.status != 'geplant').toList();
      final merged = WeekPlan(
        plan.weekStart,
        plan.phase,
        plan.summary,
        warn != null ? '${plan.rationale} (KI-Coach nicht erreichbar: $warn. Regelbasierter Plan.)' : plan.rationale,
        plan.questions,
        [...kept, ...plan.sessions.where((s) => !kept.any((k) => k.date == s.date && k.title == s.title))]
          ..sort((a, b) => '${a.date}${a.start}'.compareTo('${b.date}${b.start}')),
        unplaced: plan.unplaced,
        source: plan.source,
      );
      store.section('plans')[merged.weekStart] = merged.toJson();
      store.save();
      return merged;
    });
  }

  void setSessionStatus(DateTime weekStart, int index, String status) {
    final plan = planFor(weekStart);
    if (plan == null || index >= plan.sessions.length) return;
    plan.sessions[index].status = status;
    store.section('plans')[plan.weekStart] = plan.toJson();
    store.save();
    notifyListeners();
  }

  // ---------------------------------------------------------------- Briefing
  Briefing briefingFor(DateTime d) {
    final r = readinessFor(d);
    final raw = store.section('briefings')[iso(d)];
    if (raw != null) {
      final b = Briefing.fromJson((raw as Map).cast<String, dynamic>());
      if (b.score == r.score) return b;
    }
    return ruleBriefing(r, sessionsOn(d));
  }

  Future<Briefing?> refreshBriefing(DateTime d) {
    final coach = _coach;
    if (coach == null) {
      lastError = 'Für das KI-Briefing den Anthropic-API-Key unter „Daten“ eintragen.';
      notifyListeners();
      return Future.value(null);
    }
    return _run('Coach schreibt das Briefing …', () async {
      final b = await coach.briefing(context(d), readinessFor(d), sessionsOn(d));
      store.section('briefings')[iso(d)] = b.toJson();
      store.save();
      return b;
    });
  }

  // ---------------------------------------------------------------- Journal
  void saveJournal(String d, Map<String, dynamic> values) {
    final j = <String, dynamic>{...?journalFor(d), ...values, 'date': d, 'updated_at': clock().toIso8601String()};
    j.removeWhere((k, v) => v == null || (v is String && v.isEmpty));
    store.section('journal')[d] = j;
    if (values['weight_kg'] is num) {
      final p = Map<String, dynamic>.from(store.setting('profile') as Map);
      p['weight_kg'] = values['weight_kg'];
      store.section('settings')['profile'] = p;
    }
    store.save();
    notifyListeners();
  }

  void activityFeedback(String id, int? rpe, String? feedback) {
    final a = store.section('activities')[id] as Map?;
    if (a == null) return;
    a['rpe'] = rpe;
    a['feedback'] = feedback;
    store.save();
    notifyListeners();
  }

  // ---------------------------------------------------------------- Ernährung
  double? latestWeight(DateTime before) {
    final b = iso(before);
    final keys = store.section('journal').keys.where((k) => k.compareTo(b) <= 0).toList()..sort();
    for (final k in keys.reversed) {
      final w = journalFor(k)?['weight_kg'];
      if (w is num) return w.toDouble();
    }
    return ((store.setting('profile') as Map?)?['weight_kg'] as num?)?.toDouble();
  }

  Map<String, double> trainingLoad(DateTime d) {
    final acts = activities(addDays(d, -27), d);
    double dur(Map a) => ((a['duration_s'] as num?) ?? 0).toDouble();
    final hours = acts.fold<double>(0, (s, a) => s + dur(a) * (_kindWeight[a['kind']] ?? 0.8)) / 3600 / 4;
    final endurance = acts
            .where((a) => ['lauf', 'cardio', 'gehen'].contains(a['kind']))
            .fold<double>(0, (s, a) => s + dur(a) * (a['kind'] == 'gehen' ? 0.5 : 1)) /
        3600 /
        4;
    final planned = sessionsOn(d).fold<double>(0, (s, p) => s + minutesBetween(p.start, p.end)) / 60;
    final done = acts.where((a) => a['date'] == iso(d)).fold<double>(0, (s, a) => s + dur(a)) / 3600;
    return {
      'hours_week': (hours * 10).round() / 10,
      'endurance_hours_week': (endurance * 10).round() / 10,
      'hours_today': planned > done ? planned : done,
    };
  }

  NutritionTargets? nutritionFor(DateTime d) {
    final w = latestWeight(d);
    if (w == null || w <= 0) return null;
    final profile = Map<String, dynamic>.from(store.setting('profile') as Map);
    final base = calculateNutrition(w, profile, trainingLoad(d), today: d);
    if (profile['kcal_from_burn'] == false) return base;
    final burn = burnFor(d);
    if (burn == null) return base;
    return withBurn(base, restKcal: burn.$1, activeKcal: burn.$2, goal: (profile['goal'] as String?) ?? 'halten');
  }

  /// Ruhe- und Aktivkalorien der Uhr für einen Tag. Für heute zählen die Ruhekalorien als
  /// Schnitt der letzten 7 vollen Tage (der laufende Tag ist noch nicht komplett),
  /// die Aktivkalorien so weit, wie sie bisher angefallen sind.
  (double, double)? burnFor(DateTime d) {
    final m = metricsFor(iso(d));
    final active = (m?['active_kcal'] as num?)?.toDouble();
    double? rest;
    if (iso(d) == iso(today)) {
      final past = [
        for (var i = 1; i <= 7; i++)
          if ((metricsFor(iso(addDays(d, -i)))?['rest_kcal'] as num?) case final v? when v > 0) v.toDouble()
      ];
      if (past.isNotEmpty) rest = past.reduce((a, b) => a + b) / past.length;
    }
    rest ??= (m?['rest_kcal'] as num?)?.toDouble();
    if (rest == null || rest <= 0) return null;
    return (rest, active ?? 0);
  }

  // ---------------------------------------------------------------- Essen / Food Memory
  List<FoodEntry> foodOn(String d) {
    final list = [
      for (final e in (store.section('food')[d] as List?) ?? []) FoodEntry.fromJson((e as Map).cast<String, dynamic>())
    ];
    list.sort((a, b) => a.time.compareTo(b.time));
    return list;
  }

  FoodTotals foodTotals(String d) => totalsOf(foodOn(d));

  int _idSeq = 0;
  String _newId() => '${clock().microsecondsSinceEpoch}-${_idSeq++}';

  /// Trägt Einträge für einen Tag ein und merkt sie sich im Food Memory.
  void addFood(String d, List<FoodEntry> entries) {
    final list = (store.section('food')[d] as List?) ?? [];
    final memory = store.section('food_memory');
    final now = hhmm(clock());
    for (final e in entries) {
      final entry = e.copyWith(id: _newId(), date: d, time: e.time.isEmpty ? now : e.time);
      list.add(entry.toJson());
      remember(memory, entry);
    }
    store.section('food')[d] = list;
    store.save();
    notifyListeners();
  }

  void removeFood(String d, String id) {
    final list = (store.section('food')[d] as List?) ?? [];
    list.removeWhere((e) => e['id'] == id);
    store.section('food')[d] = list;
    store.save();
    notifyListeners();
  }

  List<Map<String, dynamic>> foodMemory({String filter = '', int limit = 30}) =>
      memoryList(store.section('food_memory'), filter: filter, limit: limit);

  void forgetFood(Map<String, dynamic> m) {
    store.section('food_memory').remove(memoryKey(m['name'] as String, (m['amount'] as String?) ?? ''));
    store.save();
    notifyListeners();
  }

  /// Produkt zum Barcode: erst aus dem eigenen Speicher, sonst von Open Food Facts.
  Future<Product?> lookupBarcode(String code) async {
    final cached = store.section('products')[code];
    if (cached != null) return Product.fromJson((cached as Map).cast<String, dynamic>());
    final p = await _run('Produkt wird gesucht …', () => FoodLookup(client: httpClient).byBarcode(code));
    if (p != null) saveProduct(p);
    return p;
  }

  void saveProduct(Product p) {
    store.section('products')[p.code] = p.toJson();
    store.save();
  }

  /// Claude schätzt Kalorien/Makros aus Freitext; das Ergebnis wird erst nach Bestätigung gespeichert.
  Future<(List<FoodEntry>, String)?> estimateFood(String text, {List<int>? image}) {
    final coach = _coach;
    if (coach == null) {
      lastError = 'Für die KI-Schätzung den Anthropic-API-Key unter „Daten“ eintragen.';
      notifyListeners();
      return Future.value(null);
    }
    return _run(image != null ? 'Claude wertet das Foto aus …' : 'Claude schätzt die Kalorien …', () async {
      final known = [
        for (final m in foodMemory(limit: 60))
          {
            for (final k in ['name', 'amount', 'kcal', 'protein', 'carbs', 'fat', 'fiber']) k: m[k]
          }
      ];
      final (items, note) = await coach.estimateFood(text, known, image: image);
      return (
        [
          for (final i in items) FoodEntry.fromJson({...i, 'id': '', 'date': iso(today), 'time': '', 'source': 'ki'})
        ],
        note,
      );
    });
  }

  // ---------------------------------------------------------------- Gamification
  List<HabitRow> habits(DateTime d) {
    final start = addDays(d, -27);
    final acts = <String, List>{};
    for (final a in activities(start, d)) {
      acts.putIfAbsent(a['date'] as String, () => []).add(a);
    }
    return dailyGrid(d, _range('metrics', start, d), _range('journal', start, d), acts);
  }

  List<WeekGoal> goalsFor(DateTime d) {
    final ws = weekStartOf(d);
    return weekGoals(activities(ws, addDays(ws, 6)), disciplines);
  }

  MarchStats marches(DateTime d) =>
      marchStats(activities(addDays(d, -27), d).where((a) => a['kind'] == 'gehen').toList());

  // ---------------------------------------------------------------- Chat
  List<Map<String, String>> chatHistory(String channel) => [
        for (final m in (store.section('chat')[channel] as List?) ?? [])
          {'role': m['role'] as String, 'content': m['content'] as String}
      ];

  void _chatAdd(String channel, String role, String content) {
    final list = (store.section('chat')[channel] as List?) ?? [];
    list.add({'role': role, 'content': content, 'ts': clock().toIso8601String()});
    store.section('chat')[channel] = list.length > 100 ? list.sublist(list.length - 100) : list;
    store.save();
  }

  Future<void> chat(String message) async {
    final coach = _coach;
    if (coach == null) {
      _chatAdd('coach', 'user', message);
      _chatAdd('coach', 'assistant',
          'Der KI-Coach ist nicht aktiv. Trag unter „Daten“ deinen Anthropic-API-Key ein, dann beantworte ich hier Fragen.');
      notifyListeners();
      return;
    }
    final history = chatHistory('coach');
    _chatAdd('coach', 'user', message);
    final answer = await _run('Coach denkt nach …', () => coach.chat(history, message, context(today)));
    if (answer != null) _chatAdd('coach', 'assistant', answer);
    notifyListeners();
  }

  void clearChat() {
    store.section('chat').remove('coach');
    store.save();
    notifyListeners();
  }

  // ---------------------------------------------------------------- Kontext
  Map<String, dynamic> context(DateTime d, {int days = 14}) {
    final start = addDays(d, -(days - 1));
    final metrics = _range('metrics', start, d);
    final journal = _range('journal', start, d);
    final s = store.allSettings;
    return {
      'heute': iso(d),
      'wochentag': weekdayNames[d.weekday - 1],
      'bereitschaft': readinessFor(d).toJson(),
      'bereitschaft_verlauf': [
        for (final p in readinessTrend(d, days: days < 14 ? days : 14)) {'date': p.$1, 'score': p.$2}
      ],
      'garmin_tageswerte': [for (final k in (metrics.keys.toList()..sort())) metrics[k]],
      'journal': [
        for (final k in (journal.keys.toList()..sort())) {...journal[k]!}..remove('updated_at')
      ],
      'aktivitaeten': [
        for (final a in activities(start, d))
          {
            for (final k in ['date', 'kind', 'name', 'duration_s', 'distance_m', 'avg_hr', 'rpe', 'feedback'])
              if (a[k] != null) k: a[k]
          }
      ],
      'plan_diese_woche': [for (final x in planFor(weekStartOf(d))?.sessions ?? <PlannedSession>[]) x.toJson()],
      'disziplinen': [
        for (final g in disciplines) {'disziplin': g.discipline.label, 'pro_woche': g.perWeek}
      ],
      'knieschonend': s['knee_friendly'] == true,
      'vorlieben': s['preferences'],
      'einschraenkungen': s['constraints'],
      'persoenliches_ziel': s['march_goal'],
      'zone2_puls': [zone2.$1, zone2.$2],
      'maersche_4_wochen': marches(d).toJson(),
      'ernaehrung_ziele': nutritionFor(d)?.toJson(),
      'essen_heute': {
        'summe': foodTotals(iso(d)).toJson(),
        'eintraege': [for (final e in foodOn(iso(d))) '${e.time} ${e.name} ${e.amount} (${e.kcal.round()} kcal)'],
      },
      'essen_7_tage': [
        for (var i = 6; i >= 1; i--)
          if (foodOn(iso(addDays(d, -i))).isNotEmpty)
            {'date': iso(addDays(d, -i)), ...foodTotals(iso(addDays(d, -i))).toJson()}
      ],
    };
  }
}
