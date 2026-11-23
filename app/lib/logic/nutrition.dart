/// Kalorien- und Makrorechner mit zwei Modi (siehe docs/ERNAEHRUNG.md).
///
/// "jan": Jans Excel-Rechner 1:1 (kcal = 26·kg, Protein 2 g/kg,
///        Fett = kcal/30, Ballaststoffe = kcal·0,014, Wasser = kg/30).
/// "wissenschaft" (Standard): Mifflin-St Jeor × PAL aus Trainingsstunden,
///        Ziel −15 % / 0 / +10 %, Protein 2,0 (2,2 im Defizit) g/kg,
///        Fett 30 % (mind. 0,8 g/kg), Ballaststoffe ≥ 30 g, Wasser 35 ml/kg
///        + 0,75 l je Trainingsstunde.
library;

const nutritionGoals = {'abnehmen': -0.15, 'halten': 0.0, 'aufbauen': 0.10};
const _palSteps = [(1.0, 1.4), (3.0, 1.55), (5.0, 1.7), (8.0, 1.85)];
const _palMax = 2.0;

class NutritionTargets {
  final String mode;
  final double weightKg;
  final int kcal, proteinG, fatG, fiberG, carbsG;
  final double waterL;
  final int proteinPct, fatPct, carbsPct;
  final double carbsGPerKg;
  final int? bmr;
  final double? pal;
  final String? goal;
  final List<String> hints;

  NutritionTargets({
    required this.mode,
    required this.weightKg,
    required this.kcal,
    required this.proteinG,
    required this.fatG,
    required this.fiberG,
    required this.carbsG,
    required this.waterL,
    required this.proteinPct,
    required this.fatPct,
    required this.carbsPct,
    required this.carbsGPerKg,
    this.bmr,
    this.pal,
    this.goal,
    List<String>? hints,
  }) : hints = hints ?? [];

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'weight_kg': weightKg,
        'kcal': kcal,
        'protein_g': proteinG,
        'fat_g': fatG,
        'fiber_g': fiberG,
        'carbs_g': carbsG,
        'water_l': waterL,
        'carbs_g_per_kg': carbsGPerKg,
        'bmr': bmr,
        'pal': pal,
        'goal': goal,
        'hints': hints,
      };
}

double _r1(double v) => (v * 10).round() / 10;

NutritionTargets _finish(
    String mode, double weight, double kcal, double protein, double fat, double fiber, double water,
    {int? bmr, double? pal, String? goal}) {
  final kcalForCarbs = kcal - protein * 4 - fat * 9; // Excel C10/D10
  final carbs = kcalForCarbs / 4 > 0 ? kcalForCarbs / 4 : 0.0;
  return NutritionTargets(
    mode: mode,
    weightKg: _r1(weight),
    kcal: kcal.round(),
    proteinG: protein.round(),
    fatG: fat.round(),
    fiberG: fiber.round(),
    carbsG: carbs.round(),
    waterL: _r1(water),
    proteinPct: (protein * 4 / kcal * 100).round(),
    fatPct: (fat * 9 / kcal * 100).round(),
    carbsPct: (carbs * 4 / kcal * 100).round(),
    carbsGPerKg: _r1(carbs / weight),
    bmr: bmr,
    pal: pal,
    goal: goal,
  );
}

void _checkWeight(double w) {
  if (w <= 0) throw ArgumentError('Körpergewicht muss größer als 0 sein');
}

NutritionTargets calculateJan(double weightKg) {
  _checkWeight(weightKg);
  final kcal = weightKg * 26;
  return _finish('jan', weightKg, kcal, weightKg * 2, kcal / 30, kcal * 0.014, weightKg / 30);
}

double mifflinStJeor(double weightKg, double heightCm, int age, String sex) {
  final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  return base + (sex == 'm' ? 5 : -161);
}

double palFromTraining(double hoursPerWeek) {
  for (final (limit, pal) in _palSteps) {
    if (hoursPerWeek < limit) return pal;
  }
  return _palMax;
}

NutritionTargets calculateScience(
  double weightKg,
  double heightCm,
  int age,
  String sex, {
  required double trainingHWeek,
  String goal = 'halten',
  double enduranceHWeek = 0,
  double trainingHToday = 0,
}) {
  _checkWeight(weightKg);
  if (!nutritionGoals.containsKey(goal)) goal = 'halten';
  final bmr = mifflinStJeor(weightKg, heightCm, age, sex);
  final pal = palFromTraining(trainingHWeek);
  final kcal = bmr * pal * (1 + nutritionGoals[goal]!);
  final protein = weightKg * (goal == 'abnehmen' ? 2.2 : 2.0);
  final fat = [kcal * 0.30 / 9, weightKg * 0.8].reduce((a, b) => a > b ? a : b);
  final fiber = [kcal / 1000 * 14, 30.0].reduce((a, b) => a > b ? a : b);
  final water = weightKg * 0.035 + trainingHToday * 0.75;
  final t = _finish('wissenschaft', weightKg, kcal, protein, fat, fiber, water, bmr: bmr.round(), pal: pal, goal: goal);
  if (enduranceHWeek >= 3 && t.carbsGPerKg < 3) {
    t.hints.add('Kohlenhydrate unter 3 g/kg bei viel Ausdauertraining: Regeneration und Leistung können leiden.');
  }
  if (goal == 'abnehmen') {
    t.hints.add('Defizit von 15 %: Gewichtsverlauf wöchentlich prüfen, Ziel 0,5–1 % pro Woche.');
  }
  return t;
}

/// Wählt den Modus aus dem Profil. Fehlen Größe/Alter/Geschlecht, gilt Jans Formel.
NutritionTargets calculateNutrition(double weightKg, Map<String, dynamic> profile, Map<String, double> training,
    {DateTime? today}) {
  final mode = profile['nutrition_mode'] ?? 'wissenschaft';
  if (mode == 'jan') return calculateJan(weightKg);
  final height = profile['height_cm'];
  final birthYear = profile['birth_year'];
  final sex = profile['sex'];
  if (height is! num || birthYear is! num || (sex != 'm' && sex != 'w')) {
    final t = calculateJan(weightKg);
    t.hints.add('Größe, Geburtsjahr und Geschlecht in den Einstellungen eintragen, dann rechne ich genauer.');
    return t;
  }
  final age = (today ?? DateTime.now()).year - birthYear.toInt();
  return calculateScience(
    weightKg,
    height.toDouble(),
    age,
    sex as String,
    trainingHWeek: training['hours_week'] ?? 0,
    goal: (profile['goal'] as String?) ?? 'halten',
    enduranceHWeek: training['endurance_hours_week'] ?? 0,
    trainingHToday: training['hours_today'] ?? 0,
  );
}
