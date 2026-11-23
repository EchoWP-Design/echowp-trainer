import 'dart:convert';
import 'dart:io';

import 'package:echowp_trainer/services/updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> rel(String tag, {String name = 'EchoWP Trainer App', bool apk = true}) => {
      'tag_name': tag,
      'name': name,
      'html_url': 'https://github.com/x/$tag',
      'assets': [
        if (apk) {'name': 'EchoWP-Trainer.apk', 'browser_download_url': 'https://dl/$tag/EchoWP-Trainer.apk'}
      ],
    };

void main() {
  test('appVersion passt zur pubspec.yaml', () {
    final v = RegExp(r'^version:\s*([0-9.]+)\+', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!;
    expect(appVersion, v.group(1));
  });

  test('Tags, Testversionen und Versionsvergleich', () {
    expect(Updater.parse(rel('app-v1.2.0-build-9'))!.build, 9);
    expect(Updater.parse(rel('v1.0.0')), isNull);
    expect(Updater.parse(rel('app-v1.0.0-build-3', name: 'X – Testversion')), isNull);
    final r = Updater.parse(rel('app-v1.1.1-build-7'))!;
    expect(Updater.isNewer(r, current: '1.1.0', build: 5), isTrue);
    expect(Updater.isNewer(r, current: '1.1.1', build: 6), isTrue);
    expect(Updater.isNewer(r, current: '1.1.1', build: 7), isFalse);
    expect(Updater.isNewer(r, current: '1.2.0', build: 1), isFalse);
    expect(Updater.compareVersions('1.10.0', '1.9.9'), 1);
  });

  test('neueste echte App-Version aus der Liste', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/repos/EchoWP-Design/echowp-trainer/releases');
      return http.Response(
          jsonEncode([
            rel('app-v1.1.0-build-5'),
            rel('app-v1.2.0-build-8', name: 'Testversion'),
            rel('app-v1.1.1-build-6'),
            rel('server-1.0'),
            rel('app-v1.1.1-build-4', apk: false),
          ]),
          200);
    });
    final r = await Updater(client: client).latest();
    expect(r!.tag, 'app-v1.1.1-build-6');
    expect(r.apkUrl, contains('EchoWP-Trainer.apk'));
  });

  test('Fehler werden verständlich gemeldet', () async {
    final client = MockClient((_) async => http.Response('', 429));
    expect(() => Updater(client: client).latest(), throwsA(isA<UpdateException>()));
  });
}
