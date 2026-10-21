import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/audio_haptics/audio_service.dart';

void main() {
  test('every Sfx has a valid 16-bit mono PCM WAV and the set fits 600 KB', () {
    var total = 0;
    for (final sfx in Sfx.values) {
      final file = File('assets/${sfx.assetPath}');
      expect(file.existsSync(), isTrue, reason: '${sfx.file}.wav missing');
      final bytes = file.readAsBytesSync();
      total += bytes.length;
      final h = ByteData.sublistView(bytes, 0, 44);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(h.getUint16(20, Endian.little), 1, reason: 'PCM');
      expect(h.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(h.getUint16(34, Endian.little), 16, reason: '16-bit');
      final rate = h.getUint32(24, Endian.little);
      final seconds = h.getUint32(40, Endian.little) / (rate * 2);
      expect(seconds, inInclusiveRange(0.03, 1.5), reason: sfx.file);
    }
    expect(total, lessThan(600 * 1024));
  });
}
