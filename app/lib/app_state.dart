/// Fachlogik der App: Daten, Sync, Score, Planung, Coach.
library;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'logic/dates.dart';
import 'logic/endurance.dart';
import 'logic/food.dart';
import 'logic/nutrition.dart';
import 'logic/planner.dart';
import 'logic/readiness.dart';
import 'logic/streaks.dart';
import 'services/coach.dart';
import 'services/food_lookup.dart';
import 'services/garmin.dart';
import 'services/storage.dart';
import 'services/updater.dart';

const _kindWeight = {'kraft': 1.0, 'cardio': 1.0, 'intervall': 1.0, 'lauf': 1.0, 'gehen': 0.8, 'mobility': 0.3};

class AppState extends ChangeNotifier {
  final Store store;
  final SecretStore secrets;
  final http.Client? httpClient;
  DateTime Function() clock;

  String? garminKey;
  String? anthropicKey;
  bool busy = false;
  String? busyLabel;
  String? lastError;

  AppState(this.store, this.secrets, {this.httpClient, DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  DateTime get today => dayOnly(clock());

  Future<void> init() async {
    garminKey = await secrets.read('garmin_key');
    anthropicKey = await secrets.read('anthropic_key');
    notifyListeners();
  }

  bool get garminConfigured => (garminKey ?? '').isNotEmpty;
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
  Map<String, dynamic>? metricsFor(String d) => (store.section('metrics')[d] as Map?)?.cast<String, dynamic>();
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
    final list = [
      for (final a in store.section('activities').values)
        if ((a['date'] as String).compareTo(s) >= 0 && (a['date'] as String).compareTo(e) <= 0)
          (a as Map).cast<String, dynamic>()
    ];
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
    if (!garminConfigured) {
      lastError = 'Erst den Garmin Personal API Key unter „Daten“ eintragen.';
      notifyListeners();
      return null;
    }
    return _run('Garmin wird synchronisiert …', () async {
      final g = _garmin();
      var nDays = 0;
      try {
        for (var i = days - 1; i >= 0; i--) {
          final m = await g.fetchDaily(addDays(today, -i));
          if (hasMetricData(m)) {
            store.section('metrics')[m['date'] as String] = m;
            nDays++;
          }
        }
        final acts = await g.fetchActivities(addDays(today, -(activityDays - 1)), today);
        final stored = store.section('activities');
        for (final a in acts) {
          final old = (stored[a['id']] as Map?) ?? {};
          stored[a['id'] as String] = {
            ...a,
            if (old['rpe'] != null) 'rpe': old['rpe'],
            if (old['feedback'] != null) 'feedback': old['feedback']
          };
        }
        final msg = '$nDays Tage und ${acts.length} Aktivitäten aktualisiert';
        store.data['last_sync'] = {'ts': clock().toIso8601String(), 'ok': true, 'message': msg};
        store.save();
        return msg;
      } catch (e) {
        store.data['last_sync'] = {'ts': clock().toIso8601String(), 'ok': false, 'message': e.toString()};
        store.save();
        rethrow;
      }
    });
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
    return calculateNutrition(w, Map<String, dynamic>.from(store.setting('profile') as Map), trainingLoad(d), today: d);
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
  Future<(List<FoodEntry>, String)?> estimateFood(String text) {
    final coach = _coach;
    if (coach == null) {
      lastError = 'Für die KI-Schätzung den Anthropic-API-Key unter „Daten“ eintragen.';
      notifyListeners();
      return Future.value(null);
    }
    return _run('Claude schätzt die Kalorien …', () async {
      final known = [
        for (final m in foodMemory(limit: 60))
          {
            for (final k in ['name', 'amount', 'kcal', 'protein', 'carbs', 'fat', 'fiber']) k: m[k]
          }
      ];
      final (items, note) = await coach.estimateFood(text, known);
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
    return weekGoals(activities(ws, addDays(ws, 6)), Map<String, dynamic>.from(store.setting('goals') as Map));
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
      'ziele': s['goals'],
      'vorlieben': s['preferences'],
      'einschraenkungen': s['constraints'],
      'marschziel': s['march_goal'],
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
