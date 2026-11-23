import 'dart:convert';
import 'dart:io';

import 'package:echowp_trainer/app_state.dart';
import 'package:echowp_trainer/services/photo.dart';
import 'package:echowp_trainer/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

List<int> _seg(int marker, List<int> data) => [0xFF, marker, (data.length + 2) >> 8, (data.length + 2) & 0xFF, ...data];

void main() {
  final jpeg = [
    0xFF, 0xD8, //
    ..._seg(0xE0, ascii.encode('JFIF\x00')),
    ..._seg(0xE1, ascii.encode('Exif\x00\x00GPS-48.9N-9.1E')),
    ..._seg(0xDB, [1, 2, 3]),
    ..._seg(0xFE, ascii.encode('Kommentar')),
    0xFF, 0xDA, 0, 4, 9, 9, 0x11, 0x22, 0xFF, 0xD9,
  ];

  test('EXIF/GPS und Kommentare werden entfernt, Bilddaten bleiben', () {
    final out = stripJpegMetadata(jpeg);
    final s = latin1.decode(out);
    expect(s, isNot(contains('GPS')));
    expect(s, isNot(contains('Kommentar')));
    expect(s, contains('JFIF'));
    expect(out.sublist(out.length - 4), [0x11, 0x22, 0xFF, 0xD9]);
    expect(stripJpegMetadata([1, 2, 3]), [1, 2, 3]);
  });

  test('Foto und Original werden gelöscht', () async {
    final dir = await Directory.systemTemp.createTemp('echowp');
    final orig = File('${dir.path}/abc.jpg')..writeAsBytesSync([1]);
    final scaled = File('${dir.path}/scaled_abc.jpg')..writeAsBytesSync([1]);
    await deletePhoto(scaled.path);
    expect(orig.existsSync(), isFalse);
    expect(scaled.existsSync(), isFalse);
    await dir.delete(recursive: true);
  });

  test('Foto geht als Bild an Claude, nichts davon landet im Speicher', () async {
    Map<String, dynamic>? sent;
    final client = MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({
            'content': [
              {
                'type': 'text',
                'text': jsonEncode({
                  'items': [
                    {
                      'name': 'Spaghetti Bolognese',
                      'amount': '400 g',
                      'kcal': 620,
                      'protein': 30,
                      'carbs': 80,
                      'fat': 18,
                      'fiber': 6
                    }
                  ],
                  'note': 'Portion geschätzt'
                })
              }
            ],
            'stop_reason': 'end_turn'
          }),
          200,
          headers: {'content-type': 'application/json'});
    });
    final st = AppState(Store.memory(), MemorySecrets({'anthropic_key': 'k'}), httpClient: client);
    await st.init();
    final res = await st.estimateFood('', image: stripJpegMetadata(jpeg));
    expect(res!.$1.single.name, 'Spaghetti Bolognese');
    final content = (sent!['messages'] as List).single['content'] as List;
    expect(content.first['type'], 'image');
    expect(content.first['source']['media_type'], 'image/jpeg');
    expect(st.store.exportJson(), isNot(contains(content.first['source']['data'] as String)));
  });
}
