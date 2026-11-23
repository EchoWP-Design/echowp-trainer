import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../logic/dates.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/session_tile.dart';

class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key});
  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  int _offset = 0;
  final _change = TextEditingController();

  @override
  void dispose() {
    _change.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final ws = addDays(weekStartOf(st.today), 7 * _offset);
    final plan = st.planFor(ws);
    final df = DateFormat('d.M.', 'de_DE');
    final acts = st.activities(ws, addDays(ws, 6));

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        EchoHeader(title: 'KW ${isoWeek(ws)} · ${df.format(ws)}–${df.format(addDays(ws, 6))}', actions: [
          IconButton(
              icon: const Icon(Icons.chevron_left, color: echoYellow), onPressed: () => setState(() => _offset--)),
          IconButton(
              icon: const Icon(Icons.chevron_right, color: echoYellow), onPressed: () => setState(() => _offset++)),
        ]),
        if (plan != null)
          SectionCard(
            title: '${plan.phase}${plan.source == 'claude' ? ' · vom Coach' : ''}',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(plan.summary, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35)),
              const SizedBox(height: 6),
              Text(plan.rationale, style: const TextStyle(color: echoMuted, fontSize: 13, height: 1.35)),
              for (final q in plan.questions)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('? $q', style: const TextStyle(color: echoYellow, fontSize: 13)),
                ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: FilledButton.icon(
            onPressed: st.busy ? null : () => st.planWeek(ws),
            icon: const Icon(Icons.auto_awesome),
            label: Text(plan == null ? 'Woche planen' : 'Woche neu planen'),
          ),
        ),
        if (plan != null)
          for (var i = 0; i < 7; i++)
            if (plan.sessions.any((s) => s.date == iso(addDays(ws, i))))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 6),
                    child: Text(
                      '${weekdayNames[i]}, ${df.format(addDays(ws, i))}',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: iso(addDays(ws, i)) == iso(st.today) ? echoYellow : Colors.white),
                    ),
                  ),
                  for (var j = 0; j < plan.sessions.length; j++)
                    if (plan.sessions[j].date == iso(addDays(ws, i)))
                      SessionTile(session: plan.sessions[j], onStatus: (s) => st.setSessionStatus(ws, j, s)),
                ]),
              ),
        if (plan != null)
          SectionCard(
            title: 'Plan ändern',
            child: Column(children: [
              TextField(
                controller: _change,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'z. B. „Donnerstag keine Zeit, Marsch lieber Samstag“'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: st.busy || !st.coachEnabled
                      ? null
                      : () async {
                          final text = _change.text.trim();
                          if (text.isEmpty) return;
                          final p = await st.planWeek(ws, instruction: text);
                          if (p != null) _change.clear();
                        },
                  child: Text(st.coachEnabled ? 'Coach anpassen lassen' : 'Braucht Anthropic-Key'),
                ),
              ),
            ]),
          ),
        SectionCard(
          title: 'Garmin-Aktivitäten dieser Woche',
          child: acts.isEmpty
              ? const Text('Keine Aktivitäten.', style: TextStyle(color: echoMuted))
              : Column(children: [
                  for (final a in acts)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(kindIcons[a['kind']] ?? Icons.directions_walk, color: echoYellow),
                      title: Text('${a['name']}'),
                      subtitle: Text(
                        '${df.format(parseIso(a['date'] as String))} · '
                        '${fmtNum(((a['duration_s'] as num?) ?? 0) / 60)} min'
                        '${a['distance_m'] != null ? ' · ${fmtNum((a['distance_m'] as num) / 1000, digits: 1)} km' : ''}'
                        '${a['avg_hr'] != null ? ' · Ø ${fmtNum(a['avg_hr'] as num)} bpm' : ''}',
                        style: const TextStyle(color: echoMuted),
                      ),
                    )
                ]),
        ),
      ],
    );
  }
}
