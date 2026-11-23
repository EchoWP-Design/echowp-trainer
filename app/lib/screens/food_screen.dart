import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../logic/dates.dart';
import '../logic/food.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/legal.dart';
import 'scanner_screen.dart';

/// Essen: Kalorien zählen mit Food Memory und KI-Schätzung aus Freitext.
class FoodScreen extends StatefulWidget {
  const FoodScreen({super.key});
  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  int _back = 0;
  final _text = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final day = addDays(st.today, -_back);
    final d = iso(day);
    final entries = st.foodOn(d);
    final t = st.foodTotals(d);
    final target = st.nutritionFor(day);
    final memory = st.foodMemory(filter: _filter, limit: 24);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        EchoHeader(title: 'Essen · ${DateFormat('EEE, d. MMMM', 'de_DE').format(day)}', actions: [
          IconButton(
              icon: const Icon(Icons.chevron_left, color: echoYellow),
              onPressed: _back >= 30 ? null : () => setState(() => _back++)),
          IconButton(
              icon: const Icon(Icons.chevron_right, color: echoYellow),
              onPressed: _back == 0 ? null : () => setState(() => _back--)),
        ]),
        SectionCard(
          title: 'Bilanz',
          trailing: target == null
              ? null
              : Text('Ziel: ${target.mode == 'jan' ? 'Jans Formel' : 'Wissenschaft'}',
                  style: const TextStyle(color: echoMuted, fontSize: 11)),
          child: Column(children: [
            _bar('Kalorien', t.kcal, target?.kcal.toDouble(), 'kcal', big: true),
            _bar('Protein', t.protein, target?.proteinG.toDouble(), 'g'),
            _bar('Kohlenhydrate', t.carbs, target?.carbsG.toDouble(), 'g'),
            _bar('Fett', t.fat, target?.fatG.toDouble(), 'g'),
            _bar('Ballaststoffe', t.fiber, target?.fiberG.toDouble(), 'g'),
            if (target == null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Für Tagesziele Gewicht im Journal oder unter „Daten“ eintragen.',
                    style: TextStyle(color: echoMuted, fontSize: 12)),
              ),
          ]),
        ),
        SectionCard(
          title: 'Was hast du gegessen?',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _text,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'z. B. „Haferflocken 60 g mit Milch und Banane“'),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: st.busy ? null : () => _scan(st, d),
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('Barcode scannen'),
              ),
              FilledButton.icon(
                onPressed: st.busy ? null : () => _estimate(st, d),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Mit KI schätzen'),
              ),
              OutlinedButton.icon(
                onPressed: () => _manual(st, d),
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Selbst eintragen'),
              ),
            ]),
            const SizedBox(height: 8),
            const Text(offAttribution, style: TextStyle(color: echoMuted, fontSize: 10)),
          ]),
        ),
        SectionCard(
          title: 'Food Memory',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (st.foodMemory(limit: 1).isEmpty)
              const Text('Alles, was du einträgst, merkt sich die App hier. Dann reicht beim nächsten Mal ein Tipp.',
                  style: TextStyle(color: echoMuted, fontSize: 13))
            else ...[
              TextField(
                decoration: const InputDecoration(
                    hintText: 'Gemerkte Lebensmittel suchen', prefixIcon: Icon(Icons.search, color: echoMuted)),
                onChanged: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: 8),
              for (final m in memory)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${m['name']}', overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${(m['amount'] as String?)?.isNotEmpty == true ? '${m['amount']} · ' : ''}'
                    '${fmtNum(m['kcal'] as num)} kcal · ${fmtNum(m['protein'] as num)} g Protein · ${m['count']}×',
                    style: const TextStyle(color: echoMuted, fontSize: 12),
                  ),
                  trailing: IconButton(
                    tooltip: 'Eintragen',
                    icon: const Icon(Icons.add_circle, color: echoYellow),
                    onPressed: () {
                      st.addFood(d, [entryFromMemory(m, id: '', date: d, time: '')]);
                      showSnack(context, '${m['name']} eingetragen');
                    },
                  ),
                  onLongPress: () => _forget(st, m),
                ),
            ],
          ]),
        ),
        SectionCard(
          title: 'Einträge',
          child: entries.isEmpty
              ? const Text('Noch nichts eingetragen.', style: TextStyle(color: echoMuted))
              : Column(children: [
                  for (final e in entries)
                    Dismissible(
                      key: ValueKey(e.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        color: const Color(0xFF3A1416),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => st.removeFood(d, e.id),
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Text(e.time, style: const TextStyle(color: echoMuted)),
                        title: Text(e.name, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${e.amount.isNotEmpty ? '${e.amount} · ' : ''}P ${fmtNum(e.protein)} · '
                          'K ${fmtNum(e.carbs)} · F ${fmtNum(e.fat)} g',
                          style: const TextStyle(color: echoMuted, fontSize: 12),
                        ),
                        trailing: Text('${e.kcal.round()} kcal',
                            style: const TextStyle(fontWeight: FontWeight.w900, color: echoYellow)),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Zum Löschen nach links wischen.', style: TextStyle(color: echoMuted, fontSize: 11)),
                  ),
                ]),
        ),
      ],
    );
  }

  Widget _bar(String label, double value, double? goal, String unit, {bool big = false}) {
    final ratio = goal == null || goal == 0 ? 0.0 : value / goal;
    final over = ratio > 1.05;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: big ? FontWeight.w900 : FontWeight.w400))),
          Text(
            goal == null ? '${value.round()} $unit' : '${value.round()} / ${goal.round()} $unit',
            style: TextStyle(fontWeight: FontWeight.w700, color: over ? const Color(0xFFFF9F1C) : Colors.white),
          ),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio.clamp(0, 1).toDouble(),
            minHeight: big ? 12 : 8,
            color: over ? const Color(0xFFFF9F1C) : echoYellow,
            backgroundColor: echoSurface2,
          ),
        ),
        if (big && goal != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              value <= goal
                  ? 'Noch ${(goal - value).round()} kcal frei'
                  : '${(value - goal).round()} kcal über dem Ziel',
              style: const TextStyle(color: echoMuted, fontSize: 12),
            ),
          ),
      ]),
    );
  }

  Future<void> _scan(AppState st, String d) async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
    if (code == null || !mounted) return;
    var product = await st.lookupBarcode(code);
    if (!mounted) return;
    if (product == null) {
      if (st.lastError != null) return;
      product = await enterProduct(context, code);
      if (product == null || !mounted) return;
      st.saveProduct(product);
    }
    final entry = await chooseAmount(context, product, d);
    if (entry == null || !mounted) return;
    st.addFood(d, [entry]);
    showSnack(context, '${entry.name}: ${entry.kcal.round()} kcal eingetragen');
  }

  Future<void> _estimate(AppState st, String d) async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      showSnack(context, 'Erst eintippen, was du gegessen hast.');
      return;
    }
    final res = await st.estimateFood(text);
    if (res == null || !mounted) return;
    final (items, note) = res;
    final selected = List<bool>.filled(items.length, true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          backgroundColor: echoSurface,
          title: Text('Schätzung: ${totalsOf([
                for (var i = 0; i < items.length; i++)
                  if (selected[i]) items[i]
              ]).kcal.round()} kcal'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              for (var i = 0; i < items.length; i++)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: echoYellow,
                  checkColor: echoBlack,
                  value: selected[i],
                  onChanged: (v) => set(() => selected[i] = v ?? false),
                  title: Text('${items[i].name} (${items[i].amount})'),
                  subtitle: Text(
                      '${items[i].kcal.round()} kcal · P ${fmtNum(items[i].protein)} · '
                      'K ${fmtNum(items[i].carbs)} · F ${fmtNum(items[i].fat)} g',
                      style: const TextStyle(color: echoMuted)),
                ),
              if (note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(note, style: const TextStyle(color: echoMuted, fontSize: 12)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Verwerfen')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eintragen')),
          ],
        ),
      ),
    );
    if (ok == true) {
      st.addFood(d, [
        for (var i = 0; i < items.length; i++)
          if (selected[i]) items[i]
      ]);
      _text.clear();
    }
  }

  Future<void> _manual(AppState st, String d) async {
    final c = {
      for (final k in ['name', 'amount', 'kcal', 'protein', 'carbs', 'fat', 'fiber']) k: TextEditingController()
    };
    if (_text.text.trim().isNotEmpty) c['name']!.text = _text.text.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: echoSurface,
        title: const Text('Selbst eintragen'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: c['name'], decoration: const InputDecoration(labelText: 'Was?')),
            const SizedBox(height: 8),
            TextField(controller: c['amount'], decoration: const InputDecoration(labelText: 'Menge (z. B. 150 g)')),
            const SizedBox(height: 8),
            for (final (k, label) in [
              ('kcal', 'Kalorien (kcal)'),
              ('protein', 'Protein (g)'),
              ('carbs', 'Kohlenhydrate (g)'),
              ('fat', 'Fett (g)'),
              ('fiber', 'Ballaststoffe (g)'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: c[k],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: label),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Speichern')),
        ],
      ),
    );
    if (ok == true && c['name']!.text.trim().isNotEmpty) {
      double n(String k) => double.tryParse(c[k]!.text.replaceAll(',', '.')) ?? 0;
      st.addFood(d, [
        FoodEntry(
          id: '',
          date: d,
          time: '',
          name: c['name']!.text.trim(),
          amount: c['amount']!.text.trim(),
          kcal: n('kcal'),
          protein: n('protein'),
          carbs: n('carbs'),
          fat: n('fat'),
          fiber: n('fiber'),
        )
      ]);
      _text.clear();
    }
    for (final x in c.values) {
      x.dispose();
    }
  }

  Future<void> _forget(AppState st, Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: echoSurface,
        title: Text('„${m['name']}“ vergessen?'),
        content: const Text('Der Eintrag verschwindet aus dem Food Memory. Bisherige Tage bleiben unverändert.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Vergessen')),
        ],
      ),
    );
    if (ok == true) st.forgetFood(m);
  }
}
