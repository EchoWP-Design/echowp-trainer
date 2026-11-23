/// Produktdaten zum Barcode aus Open Food Facts (frei, ohne Schlüssel).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../logic/food.dart';

class Product {
  final String code, name, brand;
  final double? packageG; // Inhalt des ganzen Gebindes in g bzw. ml
  final String unit; // g oder ml
  final double? servingG; // Portionsgröße laut Packung
  final double kcal100, protein100, carbs100, fat100, fiber100;

  const Product({
    required this.code,
    required this.name,
    this.brand = '',
    this.packageG,
    this.unit = 'g',
    this.servingG,
    required this.kcal100,
    this.protein100 = 0,
    this.carbs100 = 0,
    this.fat100 = 0,
    this.fiber100 = 0,
  });

  String get title => brand.isEmpty ? name : '$name ($brand)';

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'brand': brand,
        'package_g': packageG,
        'unit': unit,
        'serving_g': servingG,
        'kcal100': kcal100,
        'protein100': protein100,
        'carbs100': carbs100,
        'fat100': fat100,
        'fiber100': fiber100,
      };

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        code: j['code'] as String,
        name: j['name'] as String,
        brand: (j['brand'] as String?) ?? '',
        packageG: (j['package_g'] as num?)?.toDouble(),
        unit: (j['unit'] as String?) ?? 'g',
        servingG: (j['serving_g'] as num?)?.toDouble(),
        kcal100: (j['kcal100'] as num).toDouble(),
        protein100: ((j['protein100'] as num?) ?? 0).toDouble(),
        carbs100: ((j['carbs100'] as num?) ?? 0).toDouble(),
        fat100: ((j['fat100'] as num?) ?? 0).toDouble(),
        fiber100: ((j['fiber100'] as num?) ?? 0).toDouble(),
      );

  /// Eintrag für eine Menge in g/ml.
  FoodEntry entryFor(double grams, {required String date, String amount = ''}) {
    final f = grams / 100;
    double r(double v) => (v * f * 10).round() / 10;
    return FoodEntry(
      id: '',
      date: date,
      time: '',
      name: title,
      amount: amount.isEmpty ? '${_fmt(grams)} $unit' : amount,
      kcal: (kcal100 * f).roundToDouble(),
      protein: r(protein100),
      carbs: r(carbs100),
      fat: r(fat100),
      fiber: r(fiber100),
      source: 'barcode',
    );
  }
}

String _fmt(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

double? _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.').trim());
  return null;
}

/// Zahl aus Angaben wie "500 g", "1,5 l", "6 x 330 ml".
double? parseQuantity(String? q) {
  if (q == null) return null;
  final s = q.toLowerCase().replaceAll(',', '.');
  final multi = RegExp(r'(\d+)\s*[x×]\s*(\d+(?:\.\d+)?)\s*(kg|g|ml|cl|l)\b').firstMatch(s);
  if (multi != null) {
    return int.parse(multi.group(1)!) * _toBase(double.parse(multi.group(2)!), multi.group(3)!);
  }
  final m = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|g|ml|cl|l)\b').firstMatch(s);
  return m == null ? null : _toBase(double.parse(m.group(1)!), m.group(2)!);
}

double _toBase(double v, String unit) => switch (unit) { 'kg' || 'l' => v * 1000, 'cl' => v * 10, _ => v };

/// Wertet die Antwort von Open Food Facts aus. Gibt null zurück, wenn das Produkt fehlt
/// oder keine Kalorienangabe hat.
Product? parseOpenFoodFacts(String code, Map<String, dynamic> data) {
  if (data['status'] != 1 && data['status'] != 'success') return null;
  final p = (data['product'] as Map?)?.cast<String, dynamic>();
  if (p == null) return null;
  final n = (p['nutriments'] as Map?)?.cast<String, dynamic>() ?? {};
  var kcal = _num(n['energy-kcal_100g']);
  if (kcal == null) {
    final kj = _num(n['energy-kj_100g']) ?? _num(n['energy_100g']);
    if (kj != null) kcal = kj / 4.184;
  }
  if (kcal == null) return null;
  final unit = '${p['product_quantity_unit'] ?? ''}'.toLowerCase() == 'ml' ||
          RegExp(r'\d\s*(ml|cl|l)\b').hasMatch('${p['quantity'] ?? ''}'.toLowerCase())
      ? 'ml'
      : 'g';
  final name = '${p['product_name_de'] ?? ''}'.trim().isNotEmpty
      ? '${p['product_name_de']}'.trim()
      : '${p['product_name'] ?? ''}'.trim();
  return Product(
    code: code,
    name: name.isEmpty ? 'Produkt $code' : name,
    brand: '${p['brands'] ?? ''}'.split(',').first.trim(),
    packageG: _num(p['product_quantity']) ?? parseQuantity(p['quantity'] as String?),
    unit: unit,
    servingG: _num(p['serving_quantity']) ?? parseQuantity(p['serving_size'] as String?),
    kcal100: (kcal * 10).round() / 10,
    protein100: _num(n['proteins_100g']) ?? 0,
    carbs100: _num(n['carbohydrates_100g']) ?? 0,
    fat100: _num(n['fat_100g']) ?? 0,
    fiber100: _num(n['fiber_100g']) ?? 0,
  );
}

class FoodLookup {
  final http.Client http_;
  FoodLookup({http.Client? client}) : http_ = client ?? http.Client();

  Future<Product?> byBarcode(String code) async {
    final uri = Uri.parse('https://world.openfoodfacts.org/api/v2/product/$code.json').replace(queryParameters: {
      'fields': 'product_name,product_name_de,brands,quantity,product_quantity,product_quantity_unit,'
          'serving_size,serving_quantity,nutriments',
    });
    final http.Response resp;
    try {
      resp = await http_
          .get(uri, headers: {'User-Agent': 'EchoWP-Trainer/1.1 (Android)'}).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw Exception('Open Food Facts nicht erreichbar. Internetverbindung prüfen.');
    }
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) throw Exception('Produktsuche fehlgeschlagen (HTTP ${resp.statusCode}).');
    return parseOpenFoodFacts(code, jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
  }
}
