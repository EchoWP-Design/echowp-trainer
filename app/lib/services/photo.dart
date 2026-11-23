/// Essensfotos: nur kurz im Speicher, Metadaten (z. B. GPS) werden vor dem Senden entfernt.
library;

import 'dart:io';
import 'dart:typed_data';

/// Entfernt EXIF- und andere APPn-Blöcke (außer APP0/JFIF) aus einem JPEG.
/// Bilddaten bleiben unverändert. Kein JPEG: Rückgabe unverändert.
Uint8List stripJpegMetadata(List<int> src) {
  final b = src is Uint8List ? src : Uint8List.fromList(src);
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return b;
  final out = BytesBuilder(copy: false)..add([0xFF, 0xD8]);
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) return b; // unerwartet: lieber Original
    final marker = b[i + 1];
    if (marker == 0xDA) {
      // Start of Scan: Rest sind Bilddaten
      out.add(Uint8List.sublistView(b, i));
      return out.toBytes();
    }
    final len = (b[i + 2] << 8) | b[i + 3];
    final end = i + 2 + len;
    if (len < 2 || end > b.length) return b;
    final isApp = marker >= 0xE1 && marker <= 0xEF;
    final isComment = marker == 0xFE;
    if (!isApp && !isComment) out.add(Uint8List.sublistView(b, i, end));
    i = end;
  }
  return b;
}

/// Löscht das aufgenommene Foto und, falls verkleinert wurde, auch das Original
/// (image_picker legt `scaled_<name>` neben das Original in den Cache).
Future<void> deletePhoto(String path) async {
  final f = File(path);
  final name = f.uri.pathSegments.last;
  final paths = [
    path,
    if (name.startsWith('scaled_')) '${f.parent.path}/${name.substring('scaled_'.length)}',
  ];
  for (final p in paths) {
    try {
      final x = File(p);
      if (await x.exists()) await x.delete();
    } catch (_) {}
  }
}
