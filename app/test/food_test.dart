import 'dart:convert';

import 'package:echowp_trainer/app_state.dart';
import 'package:echowp_trainer/logic/food.dart';
import 'package:echowp_trainer/services/food_lookup.dart';
import 'package:echowp_trainer/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _now = DateTime(2026, 11, 23, 12, 30);

const _off = {
  'status': 1,
  'product': {
    'product_name': 'Skyr Natur',
    'brands': 'Milbona, Lidl',
    'quantity': '500 g',
    'product_quantity': '500',
    'serving_size': '150 g',
    'serving_quantity': 150,
    'nutriments': {
      'energy-kcal_100g': 63,
      'proteins_100g': 11,
      'carbohydrates_100g': 4,
      'fat_100g': 0.2,
      'fiber_100g': 0,
    },
  },
};

void main() {
  group('Barcode / Open Food Facts', () {
    test('Produkt mit Packungsgröße und Portion', () {
      final p = parseOpenFoodFacts('4056489', Map<String, dynamic>.from(_off))!;
      expect(p.title, 'Skyr Natur (Milbona)');
      expect(p.packageG, 500);
      expect(p.servingG, 150);
      final whole = p.entryFor(500, date: '2026-11-23');
      expect(whole.kcal, 315);
      expect(whole.protein, 55);
      expect(whole.amount, '500 g');
    });

    test('kJ wird umgerechnet, fehlende Kalorien = unbekannt', () {
      final p = parseOpenFoodFacts('1', {
        'status': 1,
        'product': {
          'product_name': 'Saft',
          'quantity': '1,5 l',
          'nutriments': {'energy-kj_100g': 184}
        }
      })!;
      expect(p.kcal100, closeTo(44, 0.1));
      expect(p.unit, 'ml');
      expect(p.packageG, 1500);
      expect(parseOpenFoodFacts('2', {'status': 0}), isNull);
      expect(
          parseOpenFoodFacts('3', {
            'status': 1,
            'product': {'product_name': 'X', 'nutriments': {}}
          }),
          isNull);
    });

    test('Mengenangaben', () {
      expect(parseQuantity('6 x 330 ml'), 1980);
      expect(parseQuantity('1 kg'), 1000);
      expect(parseQuantity('250g'), 250);
      expect(parseQuantity('Stück'), isNull);
    });
  });

  group('Food Memory', () {
    test('merkt sich Lebensmittel und sortiert nach Häufigkeit', () {
      final mem = <String, dynamic>{};
      FoodEntry e(String n, double k) =>
          FoodEntry(id: '', date: '2026-11-23', time: '', name: n, amount: '1 Stück', kcal: k);
      remember(mem, e('Banane', 105));
      remember(mem, e('Apfel', 80));
      remember(mem, e('Banane', 105));
      final list = memoryList(mem);
      expect(list.first['name'], 'Banane');
      expect(list.first['count'], 2);
      expect(memoryList(mem, filter: 'apf').single['name'], 'Apfel');
      expect(totalsOf([e('a', 100), e('b', 50.5)]).kcal, 150.5);
    });
  });

  test('App: eintragen, Memory, KI-Schätzung und Barcode mit Zwischenspeicher', () async {
    var offCalls = 0;
    final client = MockClient((req) async {
      if (req.url.host == 'world.openfoodfacts.org') {
        offCalls++;
        expect(req.headers['User-Agent'], startsWith('EchoWP-Trainer'));
        return http.Response(jsonEncode(_off), 200, headers: {'content-type': 'application/json'});
      }
      if (req.url.host == 'api.anthropic.com') {
        final body = jsonDecode(req.body) as Map;
        expect(((body['output_config'] as Map)['format'] as Map)['type'], 'json_schema');
        return http.Response(
            jsonEncode({
              'stop_reason': 'end_turn',
              'content': [
                {
                  'type': 'text',
                  'text': jsonEncode({
                    'items': [
                      {
                        'name': 'Haferflocken',
                        'amount': '60 g',
                        'kcal': 222,
                        'protein': 8,
                        'carbs': 35,
                        'fat': 4,
                        'fiber': 6
                      },
                      {
                        'name': 'Banane',
                        'amount': '1 Stück',
                        'kcal': 105,
                        'protein': 1,
                        'carbs': 24,
                        'fat': 0.4,
                        'fiber': 3
                      },
                    ],
                    'note': '',
                  })
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('', 404);
    });
    final st = AppState(Store.memory(), MemorySecrets({'anthropic_key': 'k'}), httpClient: client, clock: () => _now);
    await st.init();
    const d = '2026-11-23';

    final est = await st.estimateFood('Haferflocken mit Banane');
    expect(est!.$1.length, 2);
    st.addFood(d, est.$1);
    expect(st.foodTotals(d).kcal, 327);
    expect(st.foodOn(d).first.time, '12:30');
    expect(st.foodMemory().length, 2);

    final p = await st.lookupBarcode('4056489');
    expect(p!.name, 'Skyr Natur');
    await st.lookupBarcode('4056489');
    expect(offCalls, 1, reason: 'zweiter Scan kommt aus dem Speicher');
    st.addFood(d, [p.entryFor(150, date: d)]);
    expect(st.foodTotals(d).kcal, closeTo(327 + 94.5, 1));

    st.removeFood(d, st.foodOn(d).first.id);
    expect(st.foodOn(d).length, 2);
    expect((st.context(st.today)['essen_heute'] as Map)['summe'], isNotNull);
  });
}
