/// Update-Abruf wie bei EchoWP-Mail: neueste Version aus den GitHub-Releases lesen und die
/// passende APK über den Browser laden. Die App selbst darf bewusst keine Apps installieren
/// (Berechtigung „Andere Apps installieren“ lässt Play Protect die App blockieren).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Version dieser App, muss zu `version:` in pubspec.yaml passen (Test prüft das).
const appVersion = '1.3.0';

/// Build-Nummer (GitHub-Lauf), beim Bauen per `--dart-define=ECHOWP_BUILD=…` gesetzt.
const appBuild = int.fromEnvironment('ECHOWP_BUILD');

class UpdateException implements Exception {
  final String message;
  UpdateException(this.message);
  @override
  String toString() => message;
}

class ReleaseInfo {
  final String tag, version, pageUrl;
  final int build;
  final Map<String, String> assets; // Dateiname → Download-Link

  const ReleaseInfo(
      {required this.tag, required this.version, required this.build, required this.pageUrl, required this.assets});

  String get label => 'v$version (Build $build)';

  String? get apkUrl => assets['EchoWP-Trainer.apk'];
}

class Updater {
  static const repo = 'EchoWP-Design/echowp-trainer';
  static const _api = 'https://api.github.com/repos/$repo/releases?per_page=10';
  static final _tagRe = RegExp(r'^app-v(\d+\.\d+\.\d+)-build-(\d+)$');

  final http.Client _client;
  Updater({http.Client? client}) : _client = client ?? http.Client();

  static ReleaseInfo? parse(Map<String, dynamic> j) {
    if (j['draft'] == true || j['prerelease'] == true) return null;
    final tag = j['tag_name'] as String? ?? '';
    final m = _tagRe.firstMatch(tag);
    if (m == null) return null;
    // Testversionen (Debug-Signatur) lassen sich nicht über die echte App installieren
    if ((j['name'] as String? ?? '').contains('Testversion')) return null;
    return ReleaseInfo(
      tag: tag,
      version: m.group(1)!,
      build: int.parse(m.group(2)!),
      pageUrl: j['html_url'] as String? ?? 'https://github.com/$repo/releases',
      assets: {
        for (final a in (j['assets'] as List? ?? const []))
          if (a is Map && a['name'] is String && a['browser_download_url'] is String)
            a['name'] as String: a['browser_download_url'] as String
      },
    );
  }

  static int compareVersions(String a, String b) {
    final x = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final y = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
      if (d != 0) return d.sign;
    }
    return 0;
  }

  /// Neuer als die laufende App? Gleiche Version zählt nur bei neuerem Build.
  static bool isNewer(ReleaseInfo r, {String current = appVersion, int build = appBuild}) {
    final c = compareVersions(r.version, current);
    if (c != 0) return c > 0;
    return build > 0 && r.build > build;
  }

  /// Neueste App-Version (Releases des Servers ohne „app-“-Tag werden übersprungen).
  Future<ReleaseInfo?> latest() async {
    final http.Response r;
    try {
      r = await _client.get(Uri.parse(_api), headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'EchoWP-Trainer/$appVersion',
      }).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw UpdateException('GitHub antwortet nicht. Später erneut versuchen.');
    } catch (_) {
      throw UpdateException('Keine Verbindung zu GitHub. Update-Prüfung nicht möglich.');
    }
    if (r.statusCode == 403 || r.statusCode == 429) {
      throw UpdateException('GitHub lässt gerade keine Abfrage zu. Später erneut versuchen.');
    }
    if (r.statusCode != 200) throw UpdateException('Update-Prüfung fehlgeschlagen (HTTP ${r.statusCode}).');
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    ReleaseInfo? best;
    for (final j in list) {
      final info = parse((j as Map).cast<String, dynamic>());
      if (info == null || info.apkUrl == null) continue;
      if (best == null ||
          compareVersions(info.version, best.version) > 0 ||
          (compareVersions(info.version, best.version) == 0 && info.build > best.build)) {
        best = info;
      }
    }
    return best;
  }
}
