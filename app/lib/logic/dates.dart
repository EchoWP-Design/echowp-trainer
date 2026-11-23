/// Datumshilfen: Tage als ISO-Text (YYYY-MM-DD), Wochen ab Montag.
library;

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseIso(String s) {
  final p = s.substring(0, 10).split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Tage addieren ohne Sommerzeit-Fehler (Kalendertage, nicht 24-h-Schritte).
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

DateTime weekStartOf(DateTime d) => addDays(dayOnly(d), -(d.weekday - 1));

/// ISO-Kalenderwoche (1–53).
int isoWeek(DateTime d) {
  final day = dayOnly(d);
  final thursday = addDays(day, 4 - day.weekday);
  final firstThursday = DateTime(thursday.year, 1, 4);
  final weekOneMonday = addDays(firstThursday, -(firstThursday.weekday - 1));
  return thursday.difference(weekOneMonday).inDays ~/ 7 + 1;
}

const weekdayNames = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
const weekdayShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// Minuten zwischen zwei Uhrzeiten "HH:MM".
double minutesBetween(String? start, String? end) {
  if (start == null || end == null || start.length < 5 || end.length < 5) return 0;
  int m(String t) => int.parse(t.substring(0, 2)) * 60 + int.parse(t.substring(3, 5));
  final v = m(end) - m(start);
  return v > 0 ? v.toDouble() : 0;
}

String hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
