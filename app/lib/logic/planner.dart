/// Regelbasierte Wochenplanung (Grundlage für den KI-Coach).
///
/// 1. Phase aus mittlerer Bereitschaft und 4-Wochen-Zyklus.
/// 2. Freie Zeitfenster je Tag aus den Einstellungen.
/// 3. Bis zu vier gewählte Disziplinen mit Häufigkeit pro Woche: lange Einheiten
///    aufs Wochenende, Kraft und Intervalle abends, Ausdauer morgens, dann Mobility.
///    Knieschonend (Einstellung): Laufanteile werden durch Gehen/Ergometer ersetzt.
///    Sprünge plant die App nie.
library;

import 'dates.dart';
import 'disciplines.dart';

const strengthSplits = {
  5: ['Kettlebell Ganzkörper', 'Functional Push', 'Functional Pull', 'Hüfte & Rumpf', 'Carry & Conditioning'],
  4: ['Kettlebell Ganzkörper', 'Functional Push', 'Functional Pull', 'Hüfte & Rumpf'],
  3: ['Kettlebell Ganzkörper', 'Functional Push/Pull', 'Hüfte & Rumpf'],
  2: ['Kettlebell Ganzkörper', 'Functional Push/Pull'],
  1: ['Kettlebell Ganzkörper'],
};

const exerciseCatalog = <String, List<(String, int, String)>>{
  'Kettlebell Ganzkörper': [
    ('Kettlebell Swing', 5, '15'),
    ('Goblet Box Squat', 4, '10'),
    ('Kettlebell Clean & Press', 4, '6/Seite'),
    ('Turkish Get-up', 3, '2/Seite'),
    ('Kettlebell Row', 3, '10/Seite'),
    ('Dead Bug', 3, '10/Seite'),
  ],
  'Functional Push': [
    ('Liegestütz (ggf. erhöht)', 4, '10–15'),
    ('Kettlebell Floor Press', 4, '8/Seite'),
    ('Landmine Press', 3, '8/Seite'),
    ('Dips an Barren/Bank', 3, '8–12'),
    ('Plank Shoulder Taps', 3, '20'),
    ("Farmer's Carry", 3, '40 m'),
  ],
  'Functional Pull': [
    ('Klimmzüge / Negativ', 4, '5–8'),
    ('Inverted Row (Ringe/TRX)', 4, '10'),
    ('Kettlebell Gorilla Row', 3, '8/Seite'),
    ('Face Pulls Band', 3, '15'),
    ('Hanging Knee Raise', 3, '10'),
    ('Suitcase Carry', 3, '30 m/Seite'),
  ],
  'Functional Push/Pull': [
    ('Liegestütz', 4, '10–15'),
    ('Inverted Row', 4, '10'),
    ('Kettlebell Clean & Press', 3, '6/Seite'),
    ('Klimmzüge / Negativ', 3, '5–8'),
    ("Farmer's Carry", 3, '40 m'),
  ],
  'Hüfte & Rumpf': [
    ('Kreuzheben (Kettlebell/Trap Bar)', 4, '6–8'),
    ('Hip Thrust', 4, '10'),
    ('Step-up niedrige Box', 3, '8/Seite'),
    ('Single-Leg RDL Kettlebell', 3, '8/Seite'),
    ('Copenhagen Plank (kurz)', 3, '20 s/Seite'),
    ('Pallof Press', 3, '10/Seite'),
  ],
  'Kraft Unterkörper': [
    ('Kniebeuge auf Box (Langhantel/Goblet)', 4, '6–8'),
    ('Rumänisches Kreuzheben', 4, '8'),
    ('Hip Thrust', 3, '10'),
    ('Beinpresse (begrenzte Tiefe)', 3, '10–12'),
    ('Wadenheben', 3, '15'),
    ('Pallof Press', 3, '10/Seite'),
  ],
  'Kraft Oberkörper': [
    ('Bankdrücken / Kurzhantel-Drücken', 4, '6–8'),
    ('Rudern vorgebeugt', 4, '8'),
    ('Schulterdrücken', 3, '8–10'),
    ('Latzug / Klimmzug', 3, '8–10'),
    ('Face Pulls', 3, '15'),
    ('Bizeps/Trizeps im Wechsel', 2, '12'),
  ],
  'Kraft Ganzkörper': [
    ('Kreuzheben (Trap Bar)', 4, '5'),
    ('Kniebeuge auf Box', 3, '8'),
    ('Bankdrücken', 3, '8'),
    ('Rudern am Kabel', 3, '10'),
    ("Farmer's Carry", 3, '40 m'),
  ],
  'Eigengewicht Ganzkörper': [
    ('Liegestütz', 4, '10–15'),
    ('Klimmzüge / Inverted Row', 4, '6–10'),
    ('Box Squat Eigengewicht', 3, '15'),
    ('Glute Bridge einbeinig', 3, '10/Seite'),
    ('Pike Push-up', 3, '8'),
    ('Hollow Hold', 3, '30 s'),
  ],
  'Hyrox Stationen': [
    ('SkiErg', 4, '500 m'),
    ('Schlitten schieben/ziehen (oder KB Carry)', 4, '20 m'),
    ('Burpee ohne Sprung', 3, '10'),
    ('Rudern', 4, '500 m'),
    ('Sandbag Lunges (kurzer Schritt)', 3, '20 m'),
    ('Wall Balls', 4, '15'),
  ],
  'Hyrox Simulation': [
    ('Laufen', 4, '1 km'),
    ('je Runde 1 Station: SkiErg, Rudern, Farmer\'s Carry, Wall Balls', 4, 'je 3–4 min'),
  ],
  'Carry & Conditioning': [
    ('Zirkel 4 Runden: Kettlebell Swing', 4, '15'),
    ('Burpee ohne Sprung', 4, '8'),
    ('Bear Crawl', 4, '15 m'),
    ('Sandbag/KB Front Carry', 4, '40 m'),
    ('Mountain Climber langsam', 4, '20'),
  ],
};

const mobilityExercises = [
  ('Hüftöffner 90/90', 2, '60 s/Seite'),
  ('Thorax-Rotation', 2, '10/Seite'),
  ('Couch Stretch (Knie gepolstert)', 2, '60 s/Seite'),
  ('Cat-Cow', 2, '10'),
  ('Terminal Knee Extension mit Band', 2, '15/Seite'),
  ('Faszienrolle Waden/Oberschenkel', 1, '5 min'),
];

const durationMin = {
  'kraft': 60,
  'cardio': 45,
  'intervall': 40,
  'marsch': 100,
  'mobility': 25,
  'lauf': 40,
  'gehen': 45
};

const kindLabels = {
  'kraft': 'Kraft',
  'cardio': 'Steigungsgehen',
  'intervall': 'Intervalle',
  'marsch': 'Marsch',
  'mobility': 'Mobility',
  'lauf': 'Laufen',
  'gehen': 'Gehen',
};

class PlannedSession {
  String date, start, end, kind, title, focus;
  int? rpe;
  List<Map<String, dynamic>> exercises;
  String status; // geplant | erledigt | ausgelassen

  PlannedSession({
    required this.date,
    required this.start,
    required this.end,
    required this.kind,
    required this.title,
    required this.focus,
    this.rpe,
    List<Map<String, dynamic>>? exercises,
    this.status = 'geplant',
  }) : exercises = exercises ?? [];

  Map<String, dynamic> toJson() => {
        'date': date,
        'start': start,
        'end': end,
        'kind': kind,
        'title': title,
        'focus': focus,
        'rpe': rpe,
        'exercises': exercises,
        'status': status,
      };

  factory PlannedSession.fromJson(Map<String, dynamic> j) => PlannedSession(
        date: j['date'] as String,
        start: (j['start'] as String?) ?? '',
        end: (j['end'] as String?) ?? '',
        kind: (j['kind'] as String?) ?? 'kraft',
        title: (j['title'] as String?) ?? '',
        focus: (j['focus'] as String?) ?? '',
        rpe: (j['rpe'] as num?)?.toInt(),
        exercises: [for (final e in (j['exercises'] as List?) ?? []) Map<String, dynamic>.from(e as Map)],
        status: (j['status'] as String?) ?? 'geplant',
      );
}

class WeekPlan {
  final String weekStart, phase, summary, rationale, source;
  final List<String> questions;
  final List<PlannedSession> sessions;
  final List<String> unplaced;

  WeekPlan(this.weekStart, this.phase, this.summary, this.rationale, this.questions, this.sessions,
      {this.unplaced = const [], this.source = 'regeln'});

  Map<String, dynamic> toJson() => {
        'week_start': weekStart,
        'phase': phase,
        'summary': summary,
        'rationale': rationale,
        'questions': questions,
        'sessions': [for (final s in sessions) s.toJson()],
        'unplaced': unplaced,
        'source': source,
      };

  factory WeekPlan.fromJson(Map<String, dynamic> j) => WeekPlan(
        j['week_start'] as String,
        (j['phase'] as String?) ?? '',
        (j['summary'] as String?) ?? '',
        (j['rationale'] as String?) ?? '',
        [for (final q in (j['questions'] as List?) ?? []) q.toString()],
        [for (final s in (j['sessions'] as List?) ?? []) PlannedSession.fromJson(Map<String, dynamic>.from(s as Map))],
        unplaced: [for (final u in (j['unplaced'] as List?) ?? []) u.toString()],
        source: (j['source'] as String?) ?? 'regeln',
      );
}

/// (Phase, Volumenfaktor, RPE-Korrektur)
(String, double, int) determinePhase(DateTime weekStart, double? avgReadiness) {
  final cycleWeek = isoWeek(weekStart) % 4;
  if (avgReadiness != null && avgReadiness < 55) return ('Entlastung', 0.7, -2);
  if (cycleWeek == 0) return ('Deload', 0.7, -1);
  if (avgReadiness != null && avgReadiness < 65) return ('Erhaltung', 0.9, -1);
  return ('Aufbau', 1.0 + 0.05 * (cycleWeek - 1), 0);
}

class BusyBlock {
  final DateTime start, end;
  final String title;
  BusyBlock(this.start, this.end, this.title);
}

List<List<String>> _freeWindows(DateTime day, Map<String, dynamic> slots, List<BusyBlock> busy) {
  final out = <List<String>>[];
  for (final w in (slots['${day.weekday - 1}'] as List?) ?? []) {
    final win = [for (final x in w as List) x.toString()];
    DateTime at(String t) =>
        DateTime(day.year, day.month, day.day, int.parse(t.substring(0, 2)), int.parse(t.substring(3, 5)));
    final start = at(win[0]), end = at(win[1]);
    final blocked =
        busy.any((b) => !b.title.toLowerCase().contains('training') && b.start.isBefore(end) && b.end.isAfter(start));
    if (!blocked) out.add(win);
  }
  return out;
}

(String, String) _fit(List<String> window, int minutes) {
  final s = int.parse(window[0].substring(0, 2)) * 60 + int.parse(window[0].substring(3, 5));
  final e = int.parse(window[1].substring(0, 2)) * 60 + int.parse(window[1].substring(3, 5));
  final stop = (s + minutes) < e ? s + minutes : e;
  String f(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  return (window[0], f(stop));
}

List<Map<String, dynamic>> strengthExercises(String split, double volume, int rpeAdj, {bool knee = false}) {
  var base = exerciseCatalog[split] ?? exerciseCatalog['Kettlebell Ganzkörper']!;
  if (knee && split == 'Hyrox Simulation') {
    base = [('Rudern statt Laufen', 4, '1000 m'), base[1]];
  }
  if (knee) {
    base = [for (final e in base) e.$1.contains('Lunges') ? ('Sandbag Front Carry', e.$2, '40 m') : e];
  }
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < base.length; i++) {
    final (name, sets, reps) = base[i];
    final s = (sets * volume).round() < 2 ? 2 : (sets * volume).round();
    final rpe = (split == 'Carry & Conditioning' ? 7 : (i < 2 ? 8 : 7)) + rpeAdj;
    out.add({'name': name, 'sets': s, 'reps': reps, 'detail': '$s × $reps @ RPE $rpe'});
  }
  return out;
}

WeekPlan buildWeek(
  DateTime weekStart,
  Map<String, dynamic> settings, {
  double? avgReadiness,
  List<BusyBlock> busy = const [],
  (int, int)? zone2Hr,
}) {
  final goals = disciplinesFrom(settings);
  final knee = settings['knee_friendly'] == true;
  final slots = Map<String, dynamic>.from((settings['slots'] as Map?) ?? {});
  final (phase, volume, rpeAdj) = determinePhase(weekStart, avgReadiness);
  final easy = phase == 'Deload' || phase == 'Entlastung';
  final days = [for (var i = 0; i < 7; i++) addDays(weekStart, i)];
  final free = {for (final d in days) iso(d): _freeWindows(d, slots, busy)};
  final used = {for (final d in days) iso(d): 0};
  final kindOn = {for (final d in days) iso(d): <String>[]};
  final sessions = <PlannedSession>[];
  final unplaced = <String>[];

  (String, String)? take(DateTime day, int minutes, String prefer) {
    final wins = free[iso(day)]!;
    if (wins.isEmpty || used[iso(day)]! >= 2) return null;
    final idx = prefer == 'pm' ? wins.length - 1 : 0;
    final win = wins.removeAt(idx);
    used[iso(day)] = used[iso(day)]! + 1;
    return _fit(win, minutes);
  }

  final z2 = zone2Hr != null ? 'Zone 2 (${zone2Hr.$1}–${zone2Hr.$2} bpm)' : 'Zone 2 (locker, Sprechen möglich)';
  String text(String s, int minutes) =>
      s.replaceAll('{min}', '$minutes').replaceAll('{z2}', z2).replaceAll('{load}', easy ? '6–8 kg' : '8–12 kg');

  void add(DateTime d, (String, String) t, Discipline disc, String kind, String title, String focus, int rpe,
      [List<Map<String, dynamic>>? exercises]) {
    sessions.add(PlannedSession(
        date: iso(d), start: t.$1, end: t.$2, kind: kind, title: title, focus: focus, rpe: rpe, exercises: exercises));
    kindOn[iso(d)]!.add(disc.type);
  }

  // 1. Lange Einheiten (Marsch) aufs Wochenende, Sonntag zuerst
  final longDays = <String>[];
  for (final g in goals.where((g) => g.discipline.type == 'lang')) {
    for (var n = 0; n < g.perWeek; n++) {
      var placed = false;
      for (final d in [days[6], days[5]]) {
        if (longDays.contains(iso(d))) continue;
        final t = take(d, g.discipline.minutes, 'am');
        if (t == null) continue;
        longDays.add(iso(d));
        final minutes = (80 * volume).round();
        final load = easy ? '8–10 kg' : '10–15 kg';
        add(
            d,
            t,
            g.discipline,
            'marsch',
            'Langer Marsch (Rucking)',
            '$minutes min zügig gehen, gern mit Rucksack $load, $z2. Hügel erlaubt, '
                'bergab kurze Schritte (knieschonend).',
            5 + rpeAdj);
        placed = true;
        break;
      }
      if (!placed) unplaced.add(g.discipline.short);
    }
  }

  // 2. Kraft, Hyrox, HIIT abends, möglichst nicht zwei harte Tage am selben Tag
  for (final g in goals.where((g) => g.discipline.type == 'kraft')) {
    final disc = g.discipline;
    final splits = disc.splits.first == 'functional' ? strengthSplits[g.perWeek.clamp(1, 5)]! : disc.splits;
    var placed = 0;
    for (final pass in [0, 1]) {
      for (final d in days) {
        if (placed >= g.perWeek) break;
        if (longDays.contains(iso(d))) continue;
        if (pass == 0 && kindOn[iso(d)]!.contains('kraft')) continue;
        final t = take(d, disc.minutes, 'pm');
        if (t == null) continue;
        final name = splits[placed % splits.length];
        final title = disc.key == 'hiit' ? 'HIIT-Zirkel (ohne Sprünge)' : name;
        final focus = switch (disc.key) {
          'hyrox' => knee
              ? 'Hyrox-Stationen im Wechsel, Laufanteile auf Rudergerät oder SkiErg (Knie). Saubere Technik vor Tempo.'
              : 'Hyrox-Stationen im Wechsel mit kurzen Läufen. Saubere Technik vor Tempo.',
          'hiit' => '4 Runden, 40 s Arbeit / 20 s Pause, keine Sprünge.',
          _ => 'Schwere Grundübungen zuerst, danach leichter werden.',
        };
        add(d, t, disc, disc.kind, title, focus, disc.rpe + rpeAdj,
            strengthExercises(name, volume, rpeAdj, knee: knee));
        placed++;
      }
    }
    for (var i = placed; i < g.perWeek; i++) {
      unplaced.add(disc.short);
    }
  }

  // 3. Ausdauer morgens; beim Steigungstraining in Aufbauwochen die zweite Einheit als Intervalle
  for (final g in goals.where((g) => g.discipline.type == 'ausdauer')) {
    final disc = g.discipline;
    var placed = 0;
    for (final pass in [0, 1]) {
      for (final i in [1, 3, 5, 0, 2, 4, 6]) {
        if (placed >= g.perWeek) break;
        final d = days[i];
        if (longDays.contains(iso(d))) continue;
        if (pass == 0 && kindOn[iso(d)]!.contains('ausdauer')) continue;
        final nextIsLong = longDays.contains(iso(addDays(d, 1)));
        final interval = disc.key == 'steigung' && phase == 'Aufbau' && placed == 1 && !nextIsLong;
        final t = take(d, interval ? durationMin['intervall']! : disc.minutes, 'am');
        if (t == null) continue;
        if (interval) {
          add(
              d,
              t,
              disc,
              'intervall',
              'Steigungsintervalle Laufband',
              '8 min einlaufen (5 km/h, 3 %), dann 6 × 3 min zügig gehen bei 12–15 % Steigung '
                  'und 2 min locker bei 3 %, 5 min auslaufen. Nicht am Geländer festhalten.',
              7 + rpeAdj);
        } else {
          var focus = text(disc.focus, (disc.minutes * 0.9 * volume).round());
          var title = disc.title;
          if (knee && disc.running) {
            if (disc.key == 'laufband') {
              focus = '${(disc.minutes * 0.9 * volume).round()} min zügig gehen, 3–6 % Steigung, $z2 (knieschonend).';
            } else {
              focus = '$focus Weicher Untergrund, kurze Schritte, bei Knieschmerz auf Gehen wechseln.';
            }
          }
          if (disc.key == 'rucking') title = 'Rucking';
          add(d, t, disc, disc.kind, title, focus, disc.rpe + (disc.rpe > 3 ? rpeAdj : 0));
        }
        placed++;
      }
    }
    for (var i = placed; i < g.perWeek; i++) {
      unplaced.add(disc.short);
    }
  }

  // 4. Mobility: gewählte Einheiten, sonst eine am Tag nach dem Marsch bzw. am ersten freien Abend
  final mobilityGoal = goals.where((g) => g.discipline.type == 'ruhig').fold(0, (s, g) => s + g.perWeek);
  final mobilityDays = [
    for (final l in longDays)
      if (free.containsKey(iso(addDays(parseIso(l), 1)))) addDays(parseIso(l), 1),
    ...days,
  ];
  final mobDisc = disciplineByKey('yoga')!;
  var mob = 0;
  final mobTarget = mobilityGoal > 0 ? mobilityGoal : 1;
  final mobDone = <String>{};
  for (final d in mobilityDays) {
    if (mob >= mobTarget) break;
    if (mobDone.contains(iso(d))) continue;
    final t = take(d, durationMin['mobility']!, 'pm');
    if (t == null) continue;
    add(d, t, mobDisc, 'mobility', 'Mobility', 'Ruhig, Fokus Hüfte und Brustwirbelsäule.', 2, [
      for (final (n, s, r) in mobilityExercises) {'name': n, 'sets': s, 'reps': r, 'detail': '$s × $r'}
    ]);
    mobDone.add(iso(d));
    mob++;
  }
  for (var i = mob; i < mobilityGoal; i++) {
    unplaced.add(mobDisc.short);
  }

  sessions.sort((a, b) => '${a.date}${a.start}'.compareTo('${b.date}${b.start}'));
  final summary = switch (phase) {
    'Aufbau' => 'Aufbauwoche: Umfang leicht erhöht.',
    'Erhaltung' => 'Erhaltungswoche: Umfang halten, Intensität etwas runter.',
    'Deload' => "Deload-Woche: weniger Sätze, mehr Erholung. Danach geht's wieder hoch.",
    _ => 'Entlastungswoche: deine Bereitschaft war niedrig, wir nehmen Druck raus.',
  };
  final cycle = isoWeek(weekStart) % 4;
  var rationale = 'Mittlere Bereitschaft der letzten 7 Tage: '
      '${avgReadiness != null ? avgReadiness.round() : 'unbekannt'}. '
      'Woche ${cycle == 0 ? 4 : cycle} im 4-Wochen-Zyklus.';
  if (unplaced.isNotEmpty) rationale += ' Nicht untergebracht (keine freien Fenster): ${unplaced.join(', ')}.';
  final questions = ['Passen die Zeiten zu deinen Terminen?'];
  if (phase == 'Entlastung' || phase == 'Erhaltung') {
    questions.add('Gibt es einen Grund für die niedrige Bereitschaft (Stress, Krankheit, Knie)?');
  }
  return WeekPlan(iso(weekStart), phase, summary, rationale, questions, sessions, unplaced: unplaced);
}
