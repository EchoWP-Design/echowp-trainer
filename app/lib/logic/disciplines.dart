/// Trainingsdisziplinen: bis zu vier auswählbar, je mit Häufigkeit pro Woche.
/// Grundlage für Wochenplan, Wochenziele und KI-Coach.
library;

const maxDisciplines = 4;

class Discipline {
  final String key, label, short;

  /// Art der geplanten Einheit (PlannedSession.kind)
  final String kind;

  /// kraft = abends mit Übungen, ausdauer = morgens, lang = Wochenende, ruhig = Mobility
  final String type;
  final int minutes, rpe, maxPerWeek;
  final List<String> splits;
  final String title, focus; // {min} und {z2} werden ersetzt
  final bool running; // belastet die Knie stärker

  const Discipline(
    this.key,
    this.label,
    this.short, {
    required this.kind,
    required this.type,
    required this.minutes,
    this.rpe = 5,
    this.maxPerWeek = 7,
    this.splits = const [],
    this.title = '',
    this.focus = '',
    this.running = false,
  });
}

const disciplineCatalog = <Discipline>[
  Discipline('functional', 'Functional Fitness', 'Functional',
      kind: 'kraft', type: 'kraft', minutes: 60, rpe: 7, splits: ['functional']),
  Discipline('kraft', 'Krafttraining (Gewichte)', 'Kraft',
      kind: 'kraft',
      type: 'kraft',
      minutes: 60,
      rpe: 7,
      splits: ['Kraft Unterkörper', 'Kraft Oberkörper', 'Kraft Ganzkörper']),
  Discipline('kettlebell', 'Kettlebell', 'Kettlebell',
      kind: 'kraft',
      type: 'kraft',
      minutes: 50,
      rpe: 7,
      splits: ['Kettlebell Ganzkörper', 'Carry & Conditioning', 'Hüfte & Rumpf']),
  Discipline('eigengewicht', 'Eigengewicht / Calisthenics', 'Eigengewicht',
      kind: 'kraft',
      type: 'kraft',
      minutes: 45,
      rpe: 7,
      splits: ['Eigengewicht Ganzkörper', 'Functional Push/Pull', 'Hüfte & Rumpf']),
  Discipline('hyrox', 'Hyrox', 'Hyrox',
      kind: 'intervall',
      type: 'kraft',
      minutes: 60,
      rpe: 8,
      splits: ['Hyrox Stationen', 'Hyrox Simulation'],
      running: true),
  Discipline('hiit', 'HIIT / Zirkeltraining', 'HIIT',
      kind: 'intervall', type: 'kraft', minutes: 40, rpe: 8, splits: ['Carry & Conditioning']),
  Discipline('kardio', 'Kardio (Rad, Crosstrainer, Stepper)', 'Kardio',
      kind: 'cardio',
      type: 'ausdauer',
      minutes: 45,
      rpe: 4,
      title: 'Kardio',
      focus: '{min} min auf Rad, Crosstrainer oder Stepper, {z2}.'),
  Discipline('steigung', 'Steigungstraining Laufband', 'Steigung',
      kind: 'cardio',
      type: 'ausdauer',
      minutes: 45,
      rpe: 4,
      title: 'Steigungsgehen Laufband',
      focus: '{min} min bei 8–12 % Steigung, 5–6 km/h, {z2}.'),
  Discipline('laufband', 'Laufband', 'Laufband',
      kind: 'cardio',
      type: 'ausdauer',
      minutes: 40,
      rpe: 4,
      title: 'Laufband',
      focus: '{min} min zügig gehen oder locker laufen, 1–3 % Steigung, {z2}.',
      running: true),
  Discipline('jogging', 'Jogging / Laufen', 'Jogging',
      kind: 'lauf',
      type: 'ausdauer',
      minutes: 40,
      rpe: 5,
      title: 'Lockerer Lauf',
      focus: '{min} min locker laufen, {z2}. Am Ende 4 × 20 s etwas zügiger.',
      running: true),
  Discipline('marsch', 'Langer Marsch', 'Marsch',
      kind: 'marsch',
      type: 'lang',
      minutes: 100,
      rpe: 5,
      maxPerWeek: 2,
      title: 'Langer Marsch',
      focus: '{min} min zügig gehen, {z2}. Hügel erlaubt, bergab kurze Schritte.'),
  Discipline('rucking', 'Rucking (Gehen mit Rucksack)', 'Rucking',
      kind: 'marsch',
      type: 'ausdauer',
      minutes: 60,
      rpe: 5,
      title: 'Rucking',
      focus: '{min} min zügig gehen mit Rucksack {load}, {z2}.'),
  Discipline('spazieren', 'Spazierengehen', 'Spazieren',
      kind: 'gehen',
      type: 'ausdauer',
      minutes: 45,
      rpe: 2,
      title: 'Spaziergang',
      focus: '{min} min locker gehen, gern draußen und am Stück.'),
  Discipline('rudern', 'Rudern (Ergometer)', 'Rudern',
      kind: 'cardio',
      type: 'ausdauer',
      minutes: 40,
      rpe: 5,
      title: 'Rudern',
      focus: '{min} min rudern, Schlagzahl 20–24, {z2}. Technik vor Tempo.'),
  Discipline('radfahren', 'Radfahren', 'Rad',
      kind: 'cardio',
      type: 'ausdauer',
      minutes: 60,
      rpe: 4,
      title: 'Radfahren',
      focus: '{min} min Rad, gleichmäßig, {z2}.'),
  Discipline('schwimmen', 'Schwimmen', 'Schwimmen',
      kind: 'cardio',
      type: 'ausdauer',
      minutes: 45,
      rpe: 4,
      title: 'Schwimmen',
      focus: '{min} min schwimmen, ruhige Züge, Pausen nach Bedarf.'),
  Discipline('yoga', 'Yoga / Mobility', 'Mobility',
      kind: 'mobility',
      type: 'ruhig',
      minutes: 30,
      rpe: 2,
      title: 'Mobility',
      focus: 'Ruhig, Fokus Hüfte und Brustwirbelsäule.'),
];

Discipline? disciplineByKey(String? key) {
  for (final d in disciplineCatalog) {
    if (d.key == key) return d;
  }
  return null;
}

class DisciplineGoal {
  final Discipline discipline;
  final int perWeek;
  const DisciplineGoal(this.discipline, this.perWeek);

  Map<String, dynamic> toJson() => {'key': discipline.key, 'per_week': perWeek};
}

/// Disziplinen aus den Einstellungen. Ältere Installationen haben nur `goals`
/// (Kraft, Ausdauer, Marsch); daraus wird die gleiche Auswahl abgeleitet.
List<DisciplineGoal> disciplinesFrom(Map<String, dynamic> settings) {
  final raw = settings['disciplines'];
  if (raw is List) {
    final out = <DisciplineGoal>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final d = disciplineByKey(e['key'] as String?);
      final n = (e['per_week'] as num?)?.toInt() ?? 0;
      if (d == null || n <= 0 || out.any((g) => g.discipline.key == d.key)) continue;
      out.add(DisciplineGoal(d, n.clamp(1, d.maxPerWeek)));
      if (out.length == maxDisciplines) break;
    }
    return out;
  }
  return legacyDisciplines((settings['goals'] as Map?) ?? const {});
}

List<DisciplineGoal> legacyDisciplines(Map goals) {
  int g(String k) => (goals[k] as num?)?.toInt() ?? 0;
  return [
    if (g('strength') > 0) DisciplineGoal(disciplineByKey('functional')!, g('strength')),
    if (g('cardio') > 0) DisciplineGoal(disciplineByKey('steigung')!, g('cardio')),
    if (g('march') > 0) DisciplineGoal(disciplineByKey('marsch')!, g('march').clamp(1, 2)),
  ];
}

// ---------------------------------------------------------------- Wochenziele
/// Passt eine erfasste Aktivität (Garmin/Health Connect) zu einer Disziplin?
bool activityMatches(Discipline d, Map a) {
  final kind = a['kind'] as String? ?? '';
  final type = '${a['type'] ?? ''} ${a['name'] ?? ''}'.toLowerCase();
  final secs = (a['duration_s'] as num?) ?? 0;
  bool has(List<String> words) => words.any(type.contains);
  return switch (d.key) {
    'functional' || 'kraft' || 'kettlebell' || 'eigengewicht' => kind == 'kraft',
    'hyrox' => has(['hyrox']),
    'hiit' => has(['hiit', 'high_intensity', 'zirkel']),
    'steigung' ||
    'laufband' =>
      has(['treadmill', 'laufband', 'indoor_walking']) || (d.key == 'laufband' && kind == 'lauf' && has(['treadmill'])),
    'jogging' => kind == 'lauf',
    'marsch' => kind == 'gehen' && secs >= 3600,
    'rucking' => has(['rucking']) || (kind == 'gehen' && secs >= 2700),
    'spazieren' => kind == 'gehen',
    'rudern' => has(['row']),
    'radfahren' => has(['cycl', 'biking', 'ride', 'bike']),
    'schwimmen' => has(['swim']),
    'kardio' => kind == 'cardio',
    'yoga' => kind == 'mobility',
    _ => false,
  };
}

/// Reihenfolge beim Zuordnen: genaue Disziplinen zuerst, allgemeine zuletzt.
const _matchOrder = [
  'rudern', 'radfahren', 'schwimmen', 'hyrox', 'hiit', 'steigung', 'laufband', 'jogging', 'marsch', //
  'rucking', 'spazieren', 'functional', 'kraft', 'kettlebell', 'eigengewicht', 'kardio', 'yoga',
];

/// Wie oft jede Disziplin in der Woche schon erledigt ist. Jede Aktivität zählt nur einmal.
Map<String, int> countDone(List<Map<String, dynamic>> weekActs, List<DisciplineGoal> goals) {
  final done = {for (final g in goals) g.discipline.key: 0};
  final ordered = [...goals]
    ..sort((a, b) => _matchOrder.indexOf(a.discipline.key).compareTo(_matchOrder.indexOf(b.discipline.key)));
  for (final a in weekActs) {
    final matching = [
      for (final g in ordered)
        if (activityMatches(g.discipline, a)) g
    ];
    if (matching.isEmpty) continue;
    final open = matching.where((g) => done[g.discipline.key]! < g.perWeek);
    final pick = open.isNotEmpty ? open.first : matching.first;
    done[pick.discipline.key] = done[pick.discipline.key]! + 1;
  }
  return done;
}
