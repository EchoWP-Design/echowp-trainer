import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../logic/food.dart';
import '../services/food_lookup.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Kamera-Ansicht: liefert den ersten erkannten Produkt-Barcode (EAN/UPC) zurück.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: echoBlack,
      appBar: AppBar(
        title: const Text('Barcode scannen'),
        actions: [
          IconButton(
            tooltip: 'Licht',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          errorBuilder: (c, e) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                e.errorCode == MobileScannerErrorCode.permissionDenied
                    ? 'Kein Kamerazugriff. Bitte in den Android-Einstellungen für EchoWP Trainer die Kamera erlauben.'
                    : 'Kamera konnte nicht gestartet werden.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          onDetect: (capture) {
            if (_done) return;
            final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
            if (code == null) return;
            _done = true;
            Navigator.pop(context, code);
          },
        ),
        Center(
          child: Container(
            width: 280,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: echoYellow, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const Positioned(
          left: 16,
          right: 16,
          bottom: 32,
          child: Text('Barcode der Packung in den gelben Rahmen halten.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// Mengenwahl nach dem Scan: ganzes Gebinde, Portion laut Packung oder eigene Grammzahl.
Future<FoodEntry?> chooseAmount(BuildContext context, Product p, String date) {
  final grams = TextEditingController(text: '100');
  final count = TextEditingController(text: '1');
  var mode = p.packageG != null ? 'packung' : (p.servingG != null ? 'portion' : 'gramm');
  return showDialog<FoodEntry>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final n = double.tryParse(count.text.replaceAll(',', '.')) ?? 1;
      final (double g, String label) = switch (mode) {
        'packung' => (
            p.packageG! * n,
            n == 1
                ? 'ganze Packung (${fmtNum(p.packageG)} ${p.unit})'
                : '${fmtNum(n, digits: n % 1 == 0 ? 0 : 1)} Packungen'
          ),
        'portion' => (
            p.servingG! * n,
            '${fmtNum(n, digits: n % 1 == 0 ? 0 : 1)} Portion à ${fmtNum(p.servingG)} ${p.unit}'
          ),
        _ => ((double.tryParse(grams.text.replaceAll(',', '.')) ?? 0) * n, ''),
      };
      final e = p.entryFor(g, date: date, amount: label);
      Widget option(String value, String text) => RadioListTile<String>(
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeColor: echoYellow,
            value: value,
            title: Text(text),
          );
      return AlertDialog(
        backgroundColor: echoSurface,
        title: Text(p.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                'Pro 100 ${p.unit}: ${fmtNum(p.kcal100)} kcal · P ${fmtNum(p.protein100, digits: 1)} · '
                'K ${fmtNum(p.carbs100, digits: 1)} · F ${fmtNum(p.fat100, digits: 1)} g',
                style: const TextStyle(color: echoMuted, fontSize: 12)),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: mode,
              onChanged: (v) => set(() => mode = v ?? mode),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (p.packageG != null) option('packung', 'Ganze Packung (${fmtNum(p.packageG)} ${p.unit})'),
                if (p.servingG != null) option('portion', 'Portion laut Packung (${fmtNum(p.servingG)} ${p.unit})'),
                option('gramm', 'Eigene Menge'),
              ]),
            ),
            if (mode == 'gramm')
              TextField(
                controller: grams,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Menge in ${p.unit}'),
                onChanged: (_) => set(() {}),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: count,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Anzahl'),
              onChanged: (_) => set(() {}),
            ),
            const SizedBox(height: 12),
            Text('${e.kcal.round()} kcal · P ${fmtNum(e.protein)} · K ${fmtNum(e.carbs)} · F ${fmtNum(e.fat)} g',
                style: const TextStyle(fontWeight: FontWeight.w900, color: echoYellow)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Abbrechen')),
          FilledButton(onPressed: g > 0 ? () => Navigator.pop(c, e) : null, child: const Text('Eintragen')),
        ],
      );
    }),
  ).whenComplete(() {
    grams.dispose();
    count.dispose();
  });
}

/// Unbekannter Barcode: Werte von der Packung (pro 100 g) einmal abtippen, dann kennt die App das Produkt.
Future<Product?> enterProduct(BuildContext context, String code) async {
  final c = {
    for (final k in ['name', 'brand', 'package', 'kcal', 'protein', 'carbs', 'fat', 'fiber']) k: TextEditingController()
  };
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: echoSurface,
      title: const Text('Produkt nicht gefunden'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Barcode $code. Werte pro 100 g von der Packung abtippen, dann merkt sich die App das Produkt.',
              style: const TextStyle(color: echoMuted, fontSize: 12)),
          const SizedBox(height: 8),
          for (final (k, label, numeric) in [
            ('name', 'Produkt', false),
            ('brand', 'Marke', false),
            ('package', 'Packungsinhalt (g)', true),
            ('kcal', 'kcal pro 100 g', true),
            ('protein', 'Protein pro 100 g', true),
            ('carbs', 'Kohlenhydrate pro 100 g', true),
            ('fat', 'Fett pro 100 g', true),
            ('fiber', 'Ballaststoffe pro 100 g', true),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: c[k],
                keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
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
  double? n(String k) => double.tryParse(c[k]!.text.replaceAll(',', '.'));
  Product? p;
  if (ok == true && c['name']!.text.trim().isNotEmpty && n('kcal') != null) {
    p = Product(
      code: code,
      name: c['name']!.text.trim(),
      brand: c['brand']!.text.trim(),
      packageG: n('package'),
      kcal100: n('kcal')!,
      protein100: n('protein') ?? 0,
      carbs100: n('carbs') ?? 0,
      fat100: n('fat') ?? 0,
      fiber100: n('fiber') ?? 0,
    );
  }
  for (final x in c.values) {
    x.dispose();
  }
  return p;
}
