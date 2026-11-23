import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../logic/dates.dart';
import '../main.dart';
import '../services/coach.dart';
import '../theme.dart';
import '../widgets/common.dart';

class DataScreen extends StatefulWidget {
  const DataScreen({super.key});
  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  final _garmin = TextEditingController();
  final _anthropic = TextEditingController();

  @override
  void dispose() {
    _garmin.dispose();
    _anthropic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final profile = Map<String, dynamic>.from(st.store.setting('profile') as Map);
    final goals = Map<String, dynamic>.from(st.store.setting('goals') as Map);
    final sync = st.lastSync;

    void setProfile(String k, dynamic v) {
      profile[k] = v;
      st.store.setSetting('profile', profile);
      setState(() {});
    }

    void setGoal(String k, int v) {
      goals[k] = v;
      st.store.setSetting('goals', goals);
      setState(() {});
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const EchoHeader(title: 'Daten & Einstellungen'),
        SectionCard(
          title: 'Garmin',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              st.garminConfigured
                  ? 'Personal API Key ist gespeichert (sicherer Speicher des Handys).'
                  : 'Key in Garmin Connect (Web) unter Einstellungen → Personal API Key erstellen und hier einfügen.',
              style: const TextStyle(color: echoMuted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            _keyField(_garmin, st.garminConfigured ? 'Neuen Key einfügen' : 'Garmin Personal API Key', () async {
              await st.setKeys(garmin: _garmin.text);
              _garmin.clear();
              if (context.mounted) showSnack(context, 'Garmin-Key gespeichert');
              await st.sync(days: 14, activityDays: 60);
            }),
            const SizedBox(height: 10),
            if (sync != null)
              Text(
                '${sync['ok'] == true ? 'Letzter Sync' : 'Fehler beim Sync'}: '
                '${DateFormat('d.M. HH:mm', 'de_DE').format(DateTime.parse(sync['ts'] as String))} · ${sync['message']}',
                style: TextStyle(color: sync['ok'] == true ? echoMuted : const Color(0xFFFF5A5F), fontSize: 12),
              ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: st.busy || !st.garminConfigured ? null : () => st.sync(),
                icon: const Icon(Icons.sync),
                label: const Text('Jetzt synchronisieren'),
              ),
              OutlinedButton(
                onPressed: st.busy || !st.garminConfigured ? null : () => st.sync(days: 14, activityDays: 60),
                child: const Text('14 Tage nachladen'),
              ),
            ]),
          ]),
        ),
        SectionCard(
          title: 'KI-Coach (Claude)',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              st.coachEnabled
                  ? 'Anthropic-API-Key ist gespeichert. Ohne Key arbeitet die App mit Regeln.'
                  : 'Anthropic-API-Key (console.anthropic.com) einfügen, dann schreibt Claude Briefing, Wochenplan und Chat.',
              style: const TextStyle(color: echoMuted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            _keyField(_anthropic, st.coachEnabled ? 'Neuen Key einfügen' : 'Anthropic-API-Key', () async {
              await st.setKeys(anthropic: _anthropic.text);
              _anthropic.clear();
              if (context.mounted) showSnack(context, 'Anthropic-Key gespeichert');
            }),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: coachModels.containsKey(st.coachModel) ? st.coachModel : defaultCoachModel,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Modell'),
              items: [
                for (final e in coachModels.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))
              ],
              onChanged: (v) => st.store.setSetting('coach_model', v),
            ),
            if (st.coachEnabled)
              TextButton(
                onPressed: () async {
                  await st.setKeys(anthropic: '');
                  if (context.mounted) showSnack(context, 'Anthropic-Key entfernt');
                },
                child: const Text('Key entfernen', style: TextStyle(color: echoMuted)),
              ),
          ]),
        ),
        SectionCard(
          title: 'Profil & Ernährung',
          child: Column(children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: profile['sex'] as String?,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Geschlecht'),
                  items: const [
                    DropdownMenuItem(value: 'm', child: Text('männlich')),
                    DropdownMenuItem(value: 'w', child: Text('weiblich')),
                  ],
                  onChanged: (v) => setProfile('sex', v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _numField('Größe (cm)', profile['height_cm'] as num?, (v) => setProfile('height_cm', v)),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _numField(
                    'Geburtsjahr', profile['birth_year'] as num?, (v) => setProfile('birth_year', v?.toInt())),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _numField('Gewicht (kg)', profile['weight_kg'] as num?, (v) => setProfile('weight_kg', v)),
              ),
            ]),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: (profile['goal'] as String?) ?? 'halten',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ziel'),
              items: const [
                DropdownMenuItem(value: 'abnehmen', child: Text('Abnehmen (−15 %)')),
                DropdownMenuItem(value: 'halten', child: Text('Gewicht halten')),
                DropdownMenuItem(value: 'aufbauen', child: Text('Aufbauen (+10 %)')),
              ],
              onChanged: (v) => setProfile('goal', v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: (profile['nutrition_mode'] as String?) ?? 'wissenschaft',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Kalorienrechner'),
              items: const [
                DropdownMenuItem(value: 'wissenschaft', child: Text('Wissenschaft (Mifflin-St Jeor × PAL)')),
                DropdownMenuItem(value: 'jan', child: Text('Jans Excel-Formel (26 × kg)')),
              ],
              onChanged: (v) => setProfile('nutrition_mode', v),
            ),
          ]),
        ),
        SectionCard(
          title: 'Trainingsziele pro Woche',
          child: Column(children: [
            _stepper(
                'Functional/Kraft', (goals['strength'] as num?)?.toInt() ?? 0, 0, 6, (v) => setGoal('strength', v)),
            _stepper('Steigungsgehen', (goals['cardio'] as num?)?.toInt() ?? 0, 0, 6, (v) => setGoal('cardio', v)),
            _stepper('Langer Marsch', (goals['march'] as num?)?.toInt() ?? 0, 0, 2, (v) => setGoal('march', v)),
            _stepper('Maximalpuls', (st.store.setting('max_hr') as num?)?.toInt() ?? 190, 140, 220,
                (v) => setState(() => st.store.setSetting('max_hr', v))),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: st.store.setting('constraints') as String?,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Einschränkungen (für den Coach)'),
              onChanged: (v) => st.store.setSetting('constraints', v),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: st.store.setting('march_goal') as String?,
              decoration: const InputDecoration(labelText: 'Marsch-Ziel'),
              onChanged: (v) => st.store.setSetting('march_goal', v),
            ),
          ]),
        ),
        SectionCard(
          title: 'Garmin-Werte 14 Tage',
          child: Column(children: [
            for (var i = 0; i < 14; i++) _metricRow(st, iso(addDays(st.today, -i))),
          ]),
        ),
        SectionCard(
          title: 'Datensicherung',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Alle Daten liegen nur auf diesem Handy. Export kopiert sie als JSON in die Zwischenablage.',
                style: TextStyle(color: echoMuted, fontSize: 13)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: st.store.exportJson()));
                if (context.mounted) showSnack(context, 'Daten in die Zwischenablage kopiert');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Daten exportieren'),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _keyField(TextEditingController c, String label, Future<void> Function() onSave) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: c,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: label),
        ),
      ),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: () {
          if (c.text.trim().isNotEmpty) onSave();
        },
        child: const Text('Speichern'),
      ),
    ]);
  }

  Widget _numField(String label, num? value, void Function(num?) onChanged) {
    return TextFormField(
      initialValue: value == null ? '' : fmtNum(value, digits: value is int || value == value.roundToDouble() ? 0 : 1),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      onChanged: (t) => onChanged(num.tryParse(t.replaceAll(',', '.'))),
    );
  }

  Widget _stepper(String label, int value, int min, int max, void Function(int) onChanged) {
    return Row(children: [
      Expanded(child: Text(label)),
      IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline, color: echoYellow)),
      SizedBox(
          width: 36,
          child: Text('$value',
              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
      IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline, color: echoYellow)),
    ]);
  }

  Widget _metricRow(AppState st, String d) {
    final m = st.metricsFor(d) ?? {};
    final r = st.readinessFor(parseIso(d));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
            width: 64,
            child: Text(DateFormat('EE d.M.', 'de_DE').format(parseIso(d)),
                style: const TextStyle(color: echoMuted, fontSize: 12))),
        Expanded(
          child: Text(
            m.isEmpty
                ? 'keine Daten'
                : 'Schlaf ${fmtNum(m['sleep_hours'] as num?, digits: 1)} h · HRV ${fmtNum(m['hrv_ms'] as num?)} · '
                    'RHR ${fmtNum(m['resting_hr'] as num?)} · BB ${fmtNum(m['body_battery'] as num?)}',
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Text(r.score?.toString() ?? '–',
            style: TextStyle(fontWeight: FontWeight.w900, color: levelColors[r.level] ?? echoMuted)),
      ]),
    );
  }
}
