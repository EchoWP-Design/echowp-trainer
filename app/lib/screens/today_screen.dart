import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../logic/dates.dart';
import '../logic/planner.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/session_tile.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final d = st.today;
    final r = st.readinessFor(d);
    final m = st.metricsFor(iso(d)) ?? {};
    final b = st.briefingFor(d);
    final today = st.sessionsOn(d);
    final color = levelColors[r.level] ?? echoMuted;
    final nut = st.nutritionFor(d);
    final marches = st.marches(d);
    final sync = st.lastSync;

    return RefreshIndicator(
      color: echoYellow,
      onRefresh: () async {
        await st.sync();
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          EchoHeader(title: DateFormat('EEEE, d. MMMM', 'de_DE').format(d), actions: [
            IconButton(
              tooltip: 'Uhrdaten synchronisieren',
              icon: const Icon(Icons.sync, color: echoYellow),
              onPressed: st.busy ? null : () => st.sync(),
            ),
          ]),
          if (!st.anySource)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Willkommen! Trag unter „Daten“ deinen Garmin Personal API Key ein oder verbinde '
                    'Health Connect (Amazfit, Suunto …), dann holt die App Schlaf, HRV, Ruhepuls, Schritte, '
                    'Kalorien und Aktivitäten.'),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ScoreRing(score: r.score, color: color),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('BEREITSCHAFT',
                            style: TextStyle(color: echoYellow, fontWeight: FontWeight.w900, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(r.label, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        for (final n in r.notes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(n, style: const TextStyle(color: echoMuted, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SectionCard(
            title: 'Heute gemessen',
            trailing: sync == null
                ? null
                : Text('Sync ${DateFormat('HH:mm', 'de_DE').format(DateTime.parse(sync['ts'] as String))}',
                    style: TextStyle(color: sync['ok'] == true ? echoMuted : const Color(0xFFFF5A5F), fontSize: 11)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TileGrid(children: [
                StatTile('Schlaf', fmtNum(m['sleep_hours'] as num?, digits: 1), unit: 'h'),
                StatTile('Schlafscore', fmtNum(m['sleep_score'] as num?)),
                StatTile('HRV', fmtNum(m['hrv_ms'] as num?), unit: 'ms'),
                StatTile('Ruhepuls', fmtNum(m['resting_hr'] as num?), unit: 'bpm'),
                StatTile('Body Battery', fmtNum(m['body_battery'] as num?)),
                StatTile('Stress', fmtNum(m['stress_avg'] as num?)),
                StatTile('Schritte', fmtSteps(m['steps'] as num?)),
                StatTile('Ruhe', fmtNum(m['rest_kcal'] as num?), unit: 'kcal'),
                StatTile('Aktiv', fmtNum(m['active_kcal'] as num?), unit: 'kcal'),
                StatTile('Gesamt', fmtNum(m['total_kcal'] as num?), unit: 'kcal'),
              ]),
              if (sourceNote(m) case final note?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(note, style: const TextStyle(color: echoMuted, fontSize: 11)),
                ),
            ]),
          ),
          SectionCard(
            title: b.source == 'claude' ? 'Briefing vom Coach' : 'Briefing',
            trailing: TextButton.icon(
              onPressed: st.busy ? null : () => st.refreshBriefing(d),
              icon: const Icon(Icons.auto_awesome, size: 16, color: echoYellow),
              label: const Text('KI-Briefing', style: TextStyle(color: echoYellow)),
            ),
            child: Text(b.text, style: const TextStyle(height: 1.4)),
          ),
          SectionCard(
            title: 'Heute geplant',
            child: today.isEmpty
                ? const Text('Nichts geplant. Unter „Woche“ einen Plan erstellen.', style: TextStyle(color: echoMuted))
                : Column(children: [
                    for (final s in today)
                      SessionTile(
                        session: s,
                        onStatus: (status) => _setStatus(st, s, status),
                      )
                  ]),
          ),
          SectionCard(
            title: 'Wochenziele',
            child: Column(children: [
              for (final g in st.goalsFor(d))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    SizedBox(width: 120, child: Text(g.label)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: g.goal == 0 ? 0 : (g.done / g.goal).clamp(0, 1).toDouble(),
                          minHeight: 10,
                          color: echoYellow,
                          backgroundColor: echoSurface2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${g.done}/${g.goal}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                )
            ]),
          ),
          SectionCard(title: 'Score-Verlauf 14 Tage', child: TrendBars(points: st.readinessTrend(d))),
          SectionCard(
            title: 'Streaks',
            child: Column(children: [
              for (final h in st.habits(d))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(h.label, style: const TextStyle(fontSize: 13))),
                      Text('${h.streak} ${h.streak == 1 ? 'Tag' : 'Tage'}',
                          style: const TextStyle(color: echoYellow, fontWeight: FontWeight.w900)),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      for (final v in h.days.sublist(h.days.length - 14))
                        Expanded(
                          child: Container(
                            height: 10,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                                color: v ? echoYellow : echoSurface2, borderRadius: BorderRadius.circular(2)),
                          ),
                        )
                    ]),
                  ]),
                )
            ]),
          ),
          SectionCard(
            title: 'Märsche (4 Wochen)',
            child: TileGrid(children: [
              StatTile('Anzahl', '${marches.count}'),
              StatTile('Gesamt', fmtNum(marches.totalKm, digits: 1), unit: 'km'),
              StatTile('Längster', fmtNum(marches.longestKm, digits: 1), unit: 'km'),
              StatTile('Ø Tempo', marches.avgPace ?? '–'),
              StatTile('Zone 2', '${st.zone2.$1}–${st.zone2.$2}', unit: 'bpm'),
            ]),
          ),
          SectionCard(
            title: 'Ernährung heute',
            trailing: nut == null
                ? null
                : Text(
                    nut.fromBurn
                        ? 'Uhr-Verbrauch'
                        : nut.mode == 'jan'
                            ? 'Jans Formel'
                            : 'Wissenschaft',
                    style: const TextStyle(color: echoMuted, fontSize: 11)),
            child: nut == null
                ? const Text('Gewicht im Journal oder unter „Daten“ eintragen.', style: TextStyle(color: echoMuted))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Builder(builder: (_) {
                      final eaten = st.foodTotals(iso(d));
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (nut.fromBurn)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                'Verbrauch: Ruhe ${nut.restKcal} + Aktiv ${nut.activeKcal} = '
                                '${nut.restKcal! + nut.activeKcal!} kcal'
                                '${nut.goal != null && nut.goal != 'halten' ? ' · Ziel ${nut.goal}' : ''}',
                                style: const TextStyle(color: echoMuted, fontSize: 12),
                              ),
                            ),
                          Text(
                            'Gegessen ${eaten.kcal.round()} von ${nut.kcal} kcal · '
                            'Protein ${eaten.protein.round()} von ${nut.proteinG} g',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: (eaten.kcal / nut.kcal).clamp(0, 1).toDouble(),
                              minHeight: 10,
                              color: echoYellow,
                              backgroundColor: echoSurface2,
                            ),
                          ),
                        ]),
                      );
                    }),
                    TileGrid(children: [
                      StatTile('Kalorien', '${nut.kcal}', unit: 'kcal'),
                      StatTile('Protein', '${nut.proteinG}', unit: 'g'),
                      StatTile('Kohlenhydrate', '${nut.carbsG}', unit: 'g'),
                      StatTile('Fett', '${nut.fatG}', unit: 'g'),
                      StatTile('Ballaststoffe', '${nut.fiberG}', unit: 'g'),
                      StatTile('Wasser', fmtNum(nut.waterL, digits: 1), unit: 'l'),
                    ]),
                    for (final h in nut.hints)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(h, style: const TextStyle(color: echoMuted, fontSize: 12)),
                      ),
                  ]),
          ),
        ],
      ),
    );
  }

  void _setStatus(AppState st, PlannedSession s, String status) {
    final ws = weekStartOf(parseIso(s.date));
    final plan = st.planFor(ws);
    if (plan == null) return;
    final idx = plan.sessions.indexWhere((x) => x.date == s.date && x.start == s.start && x.title == s.title);
    if (idx >= 0) st.setSessionStatus(ws, idx, status);
  }
}

/// Schritte mit Tausenderpunkt (12.345).
String fmtSteps(num? v) {
  if (v == null) return '–';
  return NumberFormat.decimalPattern('de_DE').format(v.round());
}

/// Hinweis, welche Werte von einer anderen Uhr stammen.
String? sourceNote(Map<String, dynamic> m) {
  const names = {
    'steps_src': 'Schritte',
    'active_kcal_src': 'Aktivkalorien',
    'total_kcal_src': 'Gesamtkalorien',
    'sleep_hours_src': 'Schlaf',
  };
  final parts = [
    for (final e in names.entries)
      if (m[e.key] is String && m[e.key] != 'Garmin') '${e.value}: ${m[e.key]}'
  ];
  return parts.isEmpty ? null : 'Von anderer Uhr: ${parts.join(', ')}';
}
