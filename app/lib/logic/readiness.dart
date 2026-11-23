/// Bereitschafts-Score 0–100 aus Garmin-Daten und Gefühl.
///
/// Gewichte: Schlaf 25 %, HRV 20 %, Ruhepuls 10 %, Body Battery 15 %,
/// Gefühl 30 %. Fehlende Komponenten werden herausgerechnet. Ist das Gefühl
/// deutlich schlechter als die Messwerte, deckelt es den Score.
library;

const readinessWeights = {
  'sleep': 0.25,
  'hrv': 0.20,
  'rhr': 0.10,
  'body_battery': 0.15,
  'subjective': 0.30,
};

double _clamp(double v, [double lo = 0, double hi = 100]) => v < lo ? lo : (v > hi ? hi : v);

double _lin(double x, double x0, double y0, double x1, double y1) {
  if (x1 == x0) return y1;
  return _clamp(y0 + (x - x0) * (y1 - y0) / (x1 - x0));
}

double? _num(dynamic v) => v is num ? v.toDouble() : null;

double _mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;

class Readiness {
  final int? score;
  final String level; // push | normal | locker | recovery | unbekannt
  final String label;
  final Map<String, int?> components;
  final List<String> notes;

  const Readiness(this.score, this.level, this.label, this.components, this.notes);

  Map<String, dynamic> toJson() =>
      {'score': score, 'level': level, 'label': label, 'components': components, 'notes': notes};
}

double? sleepComponent(double? hours, double? score, double target) {
  final parts = <double>[];
  if (hours != null) parts.add(_lin(hours, target - 4, 0, target, 100));
  if (score != null) parts.add(_clamp(score));
  return parts.isEmpty ? null : _mean(parts);
}

double? hrvComponent(double? today, List<double> baseline) {
  if (today == null || baseline.length < 3) return null;
  final ratio = today / _mean(baseline);
  if (ratio >= 1) return 100;
  if (ratio >= 0.8) return _lin(ratio, 0.8, 40, 1.0, 100);
  return _lin(ratio, 0.65, 0, 0.8, 40);
}

double? rhrComponent(double? today, List<double> baseline) {
  if (today == null || baseline.length < 3) return null;
  final delta = today - _mean(baseline);
  return delta > 0 ? _lin(delta, 0, 100, 8, 20) : 100;
}

double? subjectiveComponent(Map<String, dynamic>? j) {
  if (j == null) return null;
  final vals = <double>[];
  for (final (key, inverted) in [
    ('mood', false),
    ('energy', false),
    ('motivation', false),
    ('soreness', true),
    ('stress', true),
  ]) {
    final raw = _num(j[key]);
    if (raw == null) continue;
    final v = _clamp(raw, 1, 10);
    vals.add(inverted ? (10 - v) / 9 * 100 : (v - 1) / 9 * 100);
  }
  return vals.isEmpty ? null : _mean(vals);
}

/// [metrics]/[journal]: Werte des Tages; [history]: Tageswerte der Vortage, neueste zuerst.
Readiness computeReadiness(
  Map<String, dynamic>? metrics,
  Map<String, dynamic>? journal,
  List<Map<String, dynamic>> history, {
  double sleepTarget = 8.0,
}) {
  final m = Map<String, dynamic>.from(metrics ?? {});
  final corrections = (journal?['corrections'] as Map?) ?? {};
  corrections.forEach((k, v) {
    if (v != null) m[k as String] = v;
  });

  final hist = history.take(7);
  final hrvBase = [
    for (final h in hist)
      if (_num(h['hrv_ms']) case final v? when v > 0) v
  ];
  final rhrBase = [
    for (final h in hist)
      if (_num(h['resting_hr']) case final v? when v > 0) v
  ];
  final bb = _num(m['body_battery']);
  final comps = <String, double?>{
    'sleep': sleepComponent(_num(m['sleep_hours']), _num(m['sleep_score']), sleepTarget),
    'hrv': hrvComponent(_num(m['hrv_ms']), hrvBase),
    'rhr': rhrComponent(_num(m['resting_hr']), rhrBase),
    'body_battery': bb == null ? null : _clamp(bb),
    'subjective': subjectiveComponent(journal),
  };
  final present = {
    for (final e in comps.entries)
      if (e.value != null) e.key: e.value!,
  };
  final rounded = {for (final e in comps.entries) e.key: e.value?.round()};
  if (present.isEmpty) {
    return Readiness(null, 'unbekannt', 'Keine Daten', rounded, ['Garmin synchronisieren oder Journal ausfüllen.']);
  }
  final notes = <String>[];
  final totalW = present.keys.map((k) => readinessWeights[k]!).reduce((a, b) => a + b);
  var score = present.entries.map((e) => e.value * readinessWeights[e.key]!).reduce((a, b) => a + b) / totalW;

  final subj = comps['subjective'];
  if (subj != null && subj < 40 && score > subj + 15) {
    score = subj + 15;
    notes.add('Dein Gefühl ist deutlich schlechter als die Messwerte. Ich gehe nach dem Gefühl.');
  }
  if (subj == null) notes.add('Ohne Gefühlsfeedback ist der Score ungenauer. Kurz das Journal ausfüllen.');
  if (comps['hrv'] != null && comps['hrv']! < 40) {
    notes.add('HRV klar unter deinem Schnitt: Zeichen für Belastung oder beginnenden Infekt.');
  }
  if (comps['rhr'] != null && comps['rhr']! < 50) notes.add('Ruhepuls erhöht gegenüber deinem Schnitt.');

  final s = score.round();
  final (level, label) = switch (s) {
    >= 80 => ('push', 'Push Day'),
    >= 65 => ('normal', 'Training wie geplant'),
    >= 50 => ('locker', 'Intensität reduzieren'),
    _ => ('recovery', 'Recovery / Mobility'),
  };
  return Readiness(s, level, label, rounded, notes);
}
