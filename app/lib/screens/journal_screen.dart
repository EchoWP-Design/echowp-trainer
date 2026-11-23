import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../logic/dates.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _scales = [
  ('mood', 'Stimmung', 'mies', 'super'),
  ('energy', 'Energie', 'leer', 'voll'),
  ('motivation', 'Motivation', 'keine', 'hoch'),
  ('soreness', 'Muskelkater', 'keiner', 'stark'),
  ('stress', 'Stress', 'entspannt', 'hoch'),
];

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  int _back = 0;
  String? _loadedFor;
  final Map<String, double?> _vals = {};
  final _weight = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _weight.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _load(AppState st, String d) {
    if (_loadedFor == d) return;
    _loadedFor = d;
    final j = st.journalFor(d) ?? {};
    for (final s in _scales) {
      _vals[s.$1] = (j[s.$1] as num?)?.toDouble();
    }
    _weight.text = j['weight_kg'] != null ? fmtNum(j['weight_kg'] as num, digits: 1) : '';
    _notes.text = (j['notes'] as String?) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final day = addDays(st.today, -_back);
    final d = iso(day);
    _load(st, d);
    final acts = st.activities(addDays(st.today, -6), st.today);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        EchoHeader(title: DateFormat('EEE, d. MMMM', 'de_DE').format(day), actions: [
          IconButton(
              icon: const Icon(Icons.chevron_left, color: echoYellow),
              onPressed: _back >= 13 ? null : () => setState(() => _back++)),
          IconButton(
              icon: const Icon(Icons.chevron_right, color: echoYellow),
              onPressed: _back == 0 ? null : () => setState(() => _back--)),
        ]),
        SectionCard(
          title: 'Wie geht es dir?',
          child: Column(children: [
            for (final (key, label, lo, hi) in _scales)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text(_vals[key] == null ? '–' : _vals[key]!.round().toString(),
                      style: const TextStyle(color: echoYellow, fontWeight: FontWeight.w900, fontSize: 18)),
                ]),
                Slider(
                  min: 1,
                  max: 10,
                  divisions: 9,
                  value: _vals[key] ?? 5.5,
                  inactiveColor: echoSurface2,
                  activeColor: _vals[key] == null ? echoMuted : echoYellow,
                  onChanged: (v) => setState(() => _vals[key] = v),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [
                    Text(lo, style: const TextStyle(color: echoMuted, fontSize: 11)),
                    const Spacer(),
                    Text(hi, style: const TextStyle(color: echoMuted, fontSize: 11)),
                  ]),
                ),
                const SizedBox(height: 6),
              ]),
            TextField(
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Gewicht (kg)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Notizen (Knie, Schlaf, Stimmung …)'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final w = double.tryParse(_weight.text.replaceAll(',', '.'));
                  st.saveJournal(d, {
                    for (final s in _scales) s.$1: _vals[s.$1]?.round(),
                    'weight_kg': w,
                    'notes': _notes.text.trim(),
                  });
                  showSnack(context, 'Journal gespeichert. Score: ${st.readinessFor(day).score ?? '–'}');
                },
                child: const Text('Speichern'),
              ),
            ),
          ]),
        ),
        SectionCard(
          title: 'Aktivitäten bewerten (7 Tage)',
          child: acts.isEmpty
              ? const Text('Keine Aktivitäten.', style: TextStyle(color: echoMuted))
              : Column(children: [
                  for (final a in acts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${a['name']}'),
                      subtitle: Text(
                          '${DateFormat('EEE d.M.', 'de_DE').format(parseIso(a['date'] as String))}'
                          '${a['feedback'] != null ? ' · ${a['feedback']}' : ''}',
                          style: const TextStyle(color: echoMuted)),
                      trailing: Text(a['rpe'] != null ? 'RPE ${a['rpe']}' : 'bewerten',
                          style: const TextStyle(color: echoYellow, fontWeight: FontWeight.w700)),
                      onTap: () => _rate(context, st, a),
                    )
                ]),
        ),
      ],
    );
  }

  Future<void> _rate(BuildContext context, AppState st, Map<String, dynamic> a) async {
    var rpe = ((a['rpe'] as num?) ?? 6).toDouble();
    final fb = TextEditingController(text: (a['feedback'] as String?) ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          backgroundColor: echoSurface,
          title: Text('${a['name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Anstrengung (RPE): ${rpe.round()}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Slider(min: 1, max: 10, divisions: 9, value: rpe, onChanged: (v) => set(() => rpe = v)),
            TextField(controller: fb, decoration: const InputDecoration(labelText: 'Wie lief es?')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Speichern')),
          ],
        ),
      ),
    );
    if (ok == true) st.activityFeedback(a['id'] as String, rpe.round(), fb.text.trim().isEmpty ? null : fb.text.trim());
    fb.dispose();
  }
}
