/// Ausdauerprofil: Zone-2-Pulsbereich und Kennzahlen der Märsche/Rucking.
library;

String? fmtPace(double? secPerKm) {
  if (secPerKm == null || secPerKm <= 0) return null;
  final s = secPerKm.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')} /km';
}

(int, int) zone2Range(num maxHr) => ((maxHr * 0.60).round(), (maxHr * 0.70).round());

class MarchStats {
  final int count;
  final double totalKm;
  final double? longestKm;
  final String? avgPace;
  MarchStats(this.count, this.totalKm, this.longestKm, this.avgPace);

  Map<String, dynamic> toJson() => {'count': count, 'total_km': totalKm, 'longest_km': longestKm, 'avg_pace': avgPace};
}

double _r1(double v) => (v * 10).round() / 10;

/// Märsche ab 45 Minuten aus den übergebenen Geh-Aktivitäten (typisch: 4 Wochen).
MarchStats marchStats(List<Map<String, dynamic>> walks) {
  final marches = walks.where((w) => ((w['duration_s'] as num?) ?? 0) >= 45 * 60).toList();
  final km = [for (final w in marches) ((w['distance_m'] as num?) ?? 0) / 1000];
  final withDist = marches.where((w) => ((w['distance_m'] as num?) ?? 0) > 0).toList();
  double? pace;
  if (withDist.isNotEmpty) {
    final secs = withDist.fold<double>(0, (s, w) => s + (w['duration_s'] as num));
    final dist = withDist.fold<double>(0, (s, w) => s + (w['distance_m'] as num) / 1000);
    pace = secs / dist;
  }
  return MarchStats(
    marches.length,
    _r1(km.fold(0.0, (a, b) => a + b)),
    km.isEmpty ? null : _r1(km.reduce((a, b) => a > b ? a : b)),
    fmtPace(pace),
  );
}
