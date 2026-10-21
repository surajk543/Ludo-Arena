// Renders the app icons and native launch-screen artwork from the in-app
// crest (`BrandCrestPainter` in lib/shared/widgets/brand_logo.dart), so the
// launcher, the system splash and the first app frame share one artwork.
//
// It needs the Flutter engine (dart:ui) to paint, so run it with
// `flutter test` (from frontend/):
//
//   flutter test tool/generate_brand_assets.dart
//
// Every size is painted directly from the vector artwork (no resampling) and
// written with a small deterministic PNG encoder, so the output is
// reproducible. It writes:
//
//   assets/branding/        masters (not bundled into the app):
//     app_icon_1024.png               opaque full-bleed icon (App Store)
//     play_store_icon_512.png         opaque full-bleed icon (Play listing)
//     adaptive_foreground_1024.png    crest inside the 66/108 safe zone
//     adaptive_background_1024.png    royal gradient layer
//     adaptive_monochrome_1024.png    single-color silhouette (themed icon)
//     launch_logo_1024.png            crest on transparent (launch screens)
//   ios/Runner/Assets.xcassets/AppIcon.appiconset/   every size, NO alpha
//   ios/Runner/Assets.xcassets/LaunchImage.imageset/ crest @1x/@2x/@3x
//   android/app/src/main/res/mipmap-*/              legacy + round + adaptive
//   android/app/src/main/res/drawable-*/launch_logo.png  pre-Android-12 splash
//
// The XML that references these (adaptive icon, splash styles, storyboard)
// is hand-written and committed next to them.
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/theme/app_colors.dart';
import 'package:ludo_royale/shared/widgets/brand_logo.dart';

/// Launch-screen crest width in points/dp. Matches the in-app splash
/// (`BrandLogo(size: 132)` in features/app_update/presentation/splash_screen).
const double launchLogoWidth = 132;

/// Crest height / width (BrandLogo paints `Size(size, size * 1.08)`).
const double crestAspect = 1.08;

void main() {
  test('generate brand assets', () async {
    // ---- Masters ----
    await _write(
      'assets/branding/app_icon_1024.png',
      1024,
      1024,
      paintIcon,
      opaque: true,
    );
    await _write(
      'assets/branding/play_store_icon_512.png',
      512,
      512,
      paintIcon,
      opaque: true,
    );
    await _write(
      'assets/branding/adaptive_foreground_1024.png',
      1024,
      1024,
      paintAdaptiveForeground,
    );
    await _write(
      'assets/branding/adaptive_background_1024.png',
      1024,
      1024,
      paintAdaptiveBackground,
      opaque: true,
    );
    await _write(
      'assets/branding/adaptive_monochrome_1024.png',
      1024,
      1024,
      paintAdaptiveMonochrome,
    );
    await _write(
      'assets/branding/launch_logo_1024.png',
      1024,
      (1024 * crestAspect).round(),
      paintCrestOnly,
    );

    // ---- iOS app icon (all sizes in Contents.json; opaque, no alpha) ----
    const iosIcons = {
      'Icon-App-20x20@1x.png': 20,
      'Icon-App-20x20@2x.png': 40,
      'Icon-App-20x20@3x.png': 60,
      'Icon-App-29x29@1x.png': 29,
      'Icon-App-29x29@2x.png': 58,
      'Icon-App-29x29@3x.png': 87,
      'Icon-App-40x40@1x.png': 40,
      'Icon-App-40x40@2x.png': 80,
      'Icon-App-40x40@3x.png': 120,
      'Icon-App-60x60@2x.png': 120,
      'Icon-App-60x60@3x.png': 180,
      'Icon-App-76x76@1x.png': 76,
      'Icon-App-76x76@2x.png': 152,
      'Icon-App-83.5x83.5@2x.png': 167,
      'Icon-App-1024x1024@1x.png': 1024,
    };
    for (final e in iosIcons.entries) {
      await _write(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/${e.key}',
        e.value,
        e.value,
        paintIcon,
        opaque: true,
      );
    }

    // ---- iOS launch image (crest only; background comes from the
    // LaunchBackground color set) ----
    for (final scale in [1, 2, 3]) {
      final suffix = scale == 1 ? '' : '@${scale}x';
      final w = (launchLogoWidth * scale).round();
      await _write(
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage$suffix.png',
        w,
        (w * crestAspect).round(),
        paintCrestOnly,
      );
    }

    // ---- Android ----
    const densities = {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    };
    const res = 'android/app/src/main/res';
    for (final d in densities.entries) {
      final legacy = (48 * d.value).round();
      final adaptive = (108 * d.value).round();
      await _write(
        '$res/mipmap-${d.key}/ic_launcher.png',
        legacy,
        legacy,
        paintLegacySquare,
      );
      await _write(
        '$res/mipmap-${d.key}/ic_launcher_round.png',
        legacy,
        legacy,
        paintLegacyRound,
      );
      await _write(
        '$res/mipmap-${d.key}/ic_launcher_foreground.png',
        adaptive,
        adaptive,
        paintAdaptiveForeground,
      );
      await _write(
        '$res/mipmap-${d.key}/ic_launcher_background.png',
        adaptive,
        adaptive,
        paintAdaptiveBackground,
        opaque: true,
      );
      await _write(
        '$res/mipmap-${d.key}/ic_launcher_monochrome.png',
        adaptive,
        adaptive,
        paintAdaptiveMonochrome,
      );
      final logoW = (launchLogoWidth * d.value).round();
      await _write(
        '$res/drawable-${d.key}/launch_logo.png',
        logoW,
        (logoW * crestAspect).round(),
        paintCrestOnly,
      );
    }
  });
}

// ---------------------------------------------------------------------------
// Compositions
// ---------------------------------------------------------------------------

/// Royal-violet tile with a warm glow behind the crest.
void paintTileBackground(Canvas canvas, Rect rect) {
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [BrandPalette.royal500, BrandPalette.royal850],
      ).createShader(rect),
  );
  canvas.drawRect(
    rect,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.08),
        radius: 0.62,
        colors: [
          BrandPalette.royal300.withValues(alpha: 0.35),
          BrandPalette.royal300.withValues(alpha: 0),
        ],
      ).createShader(rect),
  );
}

/// Paints the crest so that its box is [width] wide, centered on [center].
void paintCrest(
  Canvas canvas,
  Offset center,
  double width, {
  bool monochrome = false,
}) {
  final size = Size(width, width * crestAspect);
  canvas.save();
  canvas.translate(center.dx - size.width / 2, center.dy - size.height / 2);
  BrandCrestPainter(monochrome: monochrome).paint(canvas, size);
  canvas.restore();
}

/// Crest width as a fraction of the icon: a little larger on tiny icons
/// (Settings/Spotlight/notifications) so the crown and die stay legible.
double _crestFraction(double side) => side <= 64 ? 0.76 : 0.70;

/// Full-bleed square icon (iOS masks it; the Play listing masks it too).
void paintIcon(Canvas canvas, Size size) {
  final rect = Offset.zero & size;
  paintTileBackground(canvas, rect);
  paintCrest(
    canvas,
    rect.center.translate(0, size.height * 0.01),
    size.width * _crestFraction(size.width),
  );
}

/// Adaptive-icon layers use a 108-unit canvas whose central 66-unit circle
/// is always visible; the crest (52% of the canvas wide) stays inside it with
/// margin, also for the Android 12+ splash, which shows the foreground in a
/// 192/288 circle.
const double adaptiveCrestFraction = 0.52;

void paintAdaptiveForeground(Canvas canvas, Size size) {
  paintCrest(
    canvas,
    (Offset.zero & size).center.translate(0, size.height * 0.005),
    size.width * adaptiveCrestFraction,
  );
}

void paintAdaptiveBackground(Canvas canvas, Size size) =>
    paintTileBackground(canvas, Offset.zero & size);

void paintAdaptiveMonochrome(Canvas canvas, Size size) {
  paintCrest(
    canvas,
    (Offset.zero & size).center.translate(0, size.height * 0.005),
    size.width * adaptiveCrestFraction,
    monochrome: true,
  );
}

/// Legacy (API < 26) launcher icon: rounded square with a 1/24 margin.
void paintLegacySquare(Canvas canvas, Size size) {
  final inset = size.width / 24;
  final rect = (Offset.zero & size).deflate(inset);
  canvas.save();
  canvas.clipRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.2)),
  );
  paintTileBackground(canvas, rect);
  canvas.restore();
  paintCrest(
    canvas,
    rect.center.translate(0, rect.height * 0.01),
    rect.width * _crestFraction(size.width),
  );
}

/// Legacy round launcher icon.
void paintLegacyRound(Canvas canvas, Size size) {
  final inset = size.width / 24;
  final rect = (Offset.zero & size).deflate(inset);
  canvas.save();
  canvas.clipPath(Path()..addOval(rect));
  paintTileBackground(canvas, rect);
  canvas.restore();
  paintCrest(
    canvas,
    rect.center.translate(0, rect.height * 0.01),
    rect.width * 0.62,
  );
}

/// The crest alone on a transparent canvas (launch screens).
void paintCrestOnly(Canvas canvas, Size size) {
  // Leave room for the shield's drop shadow at the bottom edge.
  final width = size.width * 0.94;
  paintCrest(canvas, (Offset.zero & size).center, width);
}

// ---------------------------------------------------------------------------
// Rendering + PNG encoding
// ---------------------------------------------------------------------------

Future<void> _write(
  String path,
  int width,
  int height,
  void Function(Canvas canvas, Size size) paint, {
  bool opaque = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  paint(canvas, Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  picture.dispose();
  final rgba = data!.buffer.asUint8List();
  if (opaque) {
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] != 255) {
        throw StateError('$path: expected an opaque image (pixel ${i ~/ 4})');
      }
    }
  }
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(encodePng(width, height, rgba, alpha: !opaque));
  // ignore: avoid_print
  print('wrote $path (${width}x$height${opaque ? ', no alpha' : ''})');
}

/// Minimal deterministic PNG encoder: 8-bit RGB (alpha: false) or RGBA,
/// per-row adaptive filtering, zlib level 9.
Uint8List encodePng(
  int width,
  int height,
  Uint8List rgba, {
  required bool alpha,
}) {
  final bpp = alpha ? 4 : 3;
  final stride = width * bpp;
  final raw = Uint8List(height * (stride + 1));
  var prev = Uint8List(stride);
  final row = Uint8List(stride);
  final candidates = List.generate(5, (_) => Uint8List(stride));
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final s = (y * width + x) * 4;
      final d = x * bpp;
      row[d] = rgba[s];
      row[d + 1] = rgba[s + 1];
      row[d + 2] = rgba[s + 2];
      if (alpha) row[d + 3] = rgba[s + 3];
    }
    var best = 0;
    var bestScore = -1;
    for (var f = 0; f < 5; f++) {
      final out = candidates[f];
      var score = 0;
      for (var i = 0; i < stride; i++) {
        final a = i >= bpp ? row[i - bpp] : 0;
        final b = prev[i];
        final c = i >= bpp ? prev[i - bpp] : 0;
        final v =
            switch (f) {
              0 => row[i],
              1 => row[i] - a,
              2 => row[i] - b,
              3 => row[i] - ((a + b) >> 1),
              _ => row[i] - _paeth(a, b, c),
            } &
            0xFF;
        out[i] = v;
        score += v < 128 ? v : 256 - v;
      }
      if (bestScore < 0 || score < bestScore) {
        bestScore = score;
        best = f;
      }
    }
    final o = y * (stride + 1);
    raw[o] = best;
    raw.setRange(o + 1, o + 1 + stride, candidates[best]);
    prev = Uint8List.fromList(row);
  }

  final out = BytesBuilder();
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, alpha ? 6 : 2) // RGBA : RGB
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());
  _chunk(out, 'IDAT', Uint8List.fromList(ZLibEncoder(level: 9).convert(raw)));
  _chunk(out, 'IEND', Uint8List(0));
  return out.toBytes();
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

void _chunk(BytesBuilder out, String type, Uint8List data) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  out.add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List());
  out.add(typeBytes);
  out.add(data);
  final crc = _crc32([...typeBytes, ...data]);
  out.add((ByteData(4)..setUint32(0, crc)).buffer.asUint8List());
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
