import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/audio_haptics/audio_service.dart';

void main() {
  test('every Sfx is a 16-bit mono PCM WAV that starts at once and matches '
      'its declared length; effects fit 800 KB', () {
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
      expect(
        String.fromCharCodes(bytes.sublist(36, 40)),
        'data',
        reason: '${sfx.file}: canonical header (no metadata chunks)',
      );
      final rate = h.getUint32(24, Endian.little);
      expect(rate, anyOf(22050, 44100), reason: sfx.file);
      final frames = h.getUint32(40, Endian.little) ~/ 2;
      final seconds = frames / rate;
      expect(seconds, inInclusiveRange(0.03, 1.5), reason: sfx.file);
      expect(
        (seconds * 1000 - sfx.length.inMilliseconds).abs(),
        lessThan(15),
        reason: '${sfx.file}: Sfx.length out of date',
      );

      // No leading silence (latency): the first 20 ms are audible
      // (> -50 dBFS).
      final samples = ByteData.sublistView(bytes, 44);
      final head = (rate * 0.02).round();
      var loudest = 0;
      for (var i = 0; i < head && i < frames; i++) {
        final s = samples.getInt16(i * 2, Endian.little).abs();
        if (s > loudest) loudest = s;
      }
      expect(loudest, greaterThan(104), reason: '${sfx.file} starts silent');
    }
    expect(total, lessThan(800 * 1024));
  });

  test('jingles ship as AAC (m4a) under 200 KB and match their length', () {
    for (final jingle in Jingle.values) {
      final file = File('assets/${jingle.assetPath}');
      expect(file.existsSync(), isTrue, reason: jingle.file);
      final bytes = file.readAsBytesSync();
      expect(bytes.length, lessThan(200 * 1024), reason: jingle.file);
      expect(String.fromCharCodes(bytes.sublist(4, 8)), 'ftyp');
      expect(String.fromCharCodes(bytes.sublist(8, 11)), 'M4A');
    }
    expect(Jingle.studioIntro.length, const Duration(milliseconds: 6592));
  });

  test('the lobby music ships as AAC (m4a) under 1 MB', () {
    for (final track in MusicTrack.values) {
      final file = File('assets/${track.assetPath}');
      expect(file.existsSync(), isTrue, reason: track.file);
      final bytes = file.readAsBytesSync();
      expect(bytes.length, lessThan(1024 * 1024));
      // ISO base media file: `ftyp` box with an M4A brand.
      expect(String.fromCharCodes(bytes.sublist(4, 8)), 'ftyp');
      expect(String.fromCharCodes(bytes.sublist(8, 11)), 'M4A');
    }
  });

  test('pubspec bundles sfx/ and music/ but not the license notes', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/audio/sfx/'));
    expect(pubspec, contains('- assets/audio/music/'));
    expect(pubspec, isNot(contains('- assets/audio/\n')));
    expect(File('assets/audio/ASSET_LICENSES.md').existsSync(), isTrue);
    // The procedural generator and its WAVs are gone.
    expect(File('tool/generate_sfx.dart').existsSync(), isFalse);
    expect(
      Directory(
        'assets/audio',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.wav')),
      isEmpty,
    );
  });
}
