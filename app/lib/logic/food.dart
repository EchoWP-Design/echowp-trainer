/// Essens-Tagebuch mit Kalorien/Makros und Food Memory (gemerkte Lebensmittel).
library;

class FoodEntry {
  final String id;
  final String date; // YYYY-MM-DD
  final String time; // HH:MM
  final String name;
  final String amount; // z. B. "2 Stück", "150 g"
  final double kcal, protein, carbs, fat, fiber;
  final String source; // manuell | ki | memory

  const FoodEntry({
    required this.id,
    required this.date,
    required this.time,
    required this.name,
    this.amount = '',
    required this.kcal,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fiber = 0,
    this.source = 'manuell',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'time': time,
        'name': name,
        'amount': amount,
        'kcal': kcal,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'fiber': fiber,
        'source': source,
      };

  factory FoodEntry.fromJson(Map<String, dynamic> j) => FoodEntry(
        id: j['id'] as String,
        date: j['date'] as String,
        time: (j['time'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        amount: (j['amount'] as String?) ?? '',
        kcal: _d(j['kcal']),
        protein: _d(j['protein']),
        carbs: _d(j['carbs']),
        fat: _d(j['fat']),
        fiber: _d(j['fiber']),
        source: (j['source'] as String?) ?? 'manuell',
      );

  FoodEntry copyWith({String? id, String? date, String? time, String? source}) => FoodEntry(
        id: id ?? this.id,
        date: date ?? this.date,
        time: time ?? this.time,
        name: name,
        amount: amount,
        kcal: kcal,
        protein: protein,
        carbs: carbs,
        fat: fat,
        fiber: fiber,
        source: source ?? this.source,
      );
}

double _d(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v'.replaceAll(',', '.')) ?? 0);

class FoodTotals {
  final double kcal, protein, carbs, fat, fiber;
  const FoodTotals(this.kcal, this.protein, this.carbs, this.fat, this.fiber);

  Map<String, dynamic> toJson() => {
        'kcal': kcal.round(),
        'protein_g': protein.round(),
        'carbs_g': carbs.round(),
        'fat_g': fat.round(),
        'fiber_g': fiber.round(),
      };
}

FoodTotals totalsOf(Iterable<FoodEntry> entries) {
  var k = 0.0, p = 0.0, c = 0.0, f = 0.0, b = 0.0;
  for (final e in entries) {
    k += e.kcal;
    p += e.protein;
    c += e.carbs;
    f += e.fat;
    b += e.fiber;
  }
  return FoodTotals(k, p, c, f, b);
}

/// Schlüssel für das Food Memory: gleiche Speise + gleiche Menge = gleicher Eintrag.
String memoryKey(String name, String amount) =>
    '${name.trim().toLowerCase()}|${amount.trim().toLowerCase()}'.replaceAll(RegExp(r'\s+'), ' ');

/// Merkt sich ein gegessenes Lebensmittel (Werte des letzten Eintrags, Zähler, zuletzt benutzt).
void remember(Map<String, dynamic> memory, FoodEntry e) {
  final key = memoryKey(e.name, e.amount);
  final old = memory[key] as Map?;
  memory[key] = {
    ...e.toJson()
      ..remove('id')
      ..remove('date')
      ..remove('time')
      ..remove('source'),
    'count': ((old?['count'] as num?) ?? 0) + 1,
    'last': e.date,
  };
}

/// Gemerkte Lebensmittel, häufigste und zuletzt benutzte zuerst. Optional nach Text gefiltert.
List<Map<String, dynamic>> memoryList(Map<String, dynamic> memory, {String filter = '', int limit = 30}) {
  final f = filter.trim().toLowerCase();
  final items = [
    for (final v in memory.values)
      if (f.isEmpty || (v['name'] as String).toLowerCase().contains(f)) (v as Map).cast<String, dynamic>()
  ];
  items.sort((a, b) {
    final c = ((b['count'] as num?) ?? 0).compareTo((a['count'] as num?) ?? 0);
    return c != 0 ? c : ((b['last'] as String?) ?? '').compareTo((a['last'] as String?) ?? '');
  });
  return items.take(limit).toList();
}

FoodEntry entryFromMemory(Map<String, dynamic> m, {required String id, required String date, required String time}) =>
    FoodEntry.fromJson({...m, 'id': id, 'date': date, 'time': time, 'source': 'memory'});
