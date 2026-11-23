/// Gewohnheiten, Streaks und Wochenziele.
library;

import 'disciplines.dart';

import 'dates.dart';

const dailyHabits = [
  ('garmin', 'Uhr synchronisiert'),
  ('sleep7', 'Mehr als 7 h Schlaf'),
  ('journal', 'Journal ausgefüllt'),
  ('training', 'Bewegt (Training)'),
];

class HabitRow {
  final String key, label;
  final List<bool> days;
  final int streak;
  HabitRow(this.key, this.label, this.days, this.streak);
}

/// Zählt von heute rückwärts. Ein noch offener heutiger Tag bricht nichts.
int streakOf(List<bool> values) {
  var vals = List<bool>.from(values);
  if (vals.isNotEmpty && !vals.last) vals = vals.sublist(0, vals.length - 1);
  var n = 0;
  for (final v in vals.reversed) {
    if (!v) break;
    n++;
  }
  return n;
}

List<HabitRow> dailyGrid(DateTime today, Map<String, Map<String, dynamic>> metrics,
    Map<String, Map<String, dynamic>> journal, Map<String, List> activities,
    {int days = 28}) {
  final dates = [for (var i = days - 1; i >= 0; i--) iso(addDays(today, -i))];
  final grid = {for (final h in dailyHabits) h.$1: <bool>[]};
  for (final d in dates) {
    final m = metrics[d] ?? const {};
    final j = journal[d] ?? const {};
    final corr = (j['corrections'] as Map?) ?? const {};
    final sleep = (corr['sleep_hours'] ?? m['sleep_hours']) as num?;
    grid['garmin']!.add(m.isNotEmpty && (m['source'] ?? '') != '' && m['source'] != 'manuell');
    grid['sleep7']!.add(sleep != null && sleep >= 7);
    grid['journal']!.add(j['mood'] != null || j['energy'] != null || ((j['notes'] as String?) ?? '').isNotEmpty);
    grid['training']!.add((activities[d] ?? const []).isNotEmpty);
  }
  return [for (final (k, label) in dailyHabits) HabitRow(k, label, grid[k]!, streakOf(grid[k]!))];
}

class WeekGoal {
  final String key, label;
  final int done, goal;
  WeekGoal(this.key, this.label, this.done, this.goal);
}

List<WeekGoal> weekGoals(List<Map<String, dynamic>> weekActs, List<DisciplineGoal> goals) {
  final done = countDone(weekActs, goals);
  return [for (final g in goals) WeekGoal(g.discipline.key, g.discipline.short, done[g.discipline.key]!, g.perWeek)];
}
