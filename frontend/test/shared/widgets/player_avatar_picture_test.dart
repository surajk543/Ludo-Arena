import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/assets/profile_picture_cache.dart';
import 'package:ludo_arena/shared/widgets/widgets.dart';
import 'package:lottie/lottie.dart';

import '../../helpers/picture_fixtures.dart';
import 'widget_harness.dart';

Finder get _builtIn => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is AvatarPainter,
);

void main() {
  late FakeProfilePictureCache cache;

  setUp(() => cache = FakeProfilePictureCache());

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      await buildHarness(
        Center(child: child),
        overrides: [profilePictureCacheProvider.overrideWithValue(cache)],
        disableAnimations: reduceMotion,
      ),
    );
    await tester.pump();
  }

  testWidgets('without a picture: the built-in avatar, no cache access', (
    tester,
  ) async {
    await pump(tester, const PlayerAvatar(avatarIndex: 3, size: 64));
    expect(_builtIn, findsOneWidget);
    expect(find.byType(ProfilePictureView), findsNothing);
    expect(cache.requested, isEmpty);
  });

  testWidgets('a cached animated picture replaces the built-in avatar, '
      'inside the frame', (tester) async {
    final p = lottiePicture();
    cache.ready[p.path] = LoadedLottiePicture(testComposition());
    await pump(
      tester,
      PlayerAvatar(avatarIndex: 3, picture: p, frameId: 'frame_gold', size: 80),
    );
    expect(find.byType(Lottie), findsOneWidget);
    expect(tester.widget<Lottie>(find.byType(Lottie)).animate, isTrue);
    expect(_builtIn, findsNothing);
    // The frame is still drawn around the picture.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter is AvatarFramePainter &&
            (w.painter! as AvatarFramePainter).frameId == 'frame_gold',
      ),
      findsOneWidget,
    );
    // The portrait keeps the frame's portrait size.
    expect(
      tester.getSize(find.byType(ProfilePictureView)),
      Size.square(80 * PlayerAvatar.portraitFraction('frame_gold')),
    );
  });

  testWidgets('reduced motion shows the first frame without animating', (
    tester,
  ) async {
    final p = lottiePicture();
    cache.ready[p.path] = LoadedLottiePicture(testComposition());
    await pump(
      tester,
      PlayerAvatar(avatarIndex: 0, picture: p),
      reduceMotion: true,
    );
    expect(tester.widget<Lottie>(find.byType(Lottie)).animate, isFalse);
    await tester.pumpAndSettle(); // nothing ticks
  });

  testWidgets('animatePicture: false never animates', (tester) async {
    final p = lottiePicture();
    cache.ready[p.path] = LoadedLottiePicture(testComposition());
    await pump(
      tester,
      PlayerAvatar(avatarIndex: 0, picture: p, animatePicture: false),
    );
    expect(tester.widget<Lottie>(find.byType(Lottie)).animate, isFalse);
  });

  testWidgets('an unavailable picture keeps the built-in avatar', (
    tester,
  ) async {
    final p = imagePicture('offline');
    await pump(tester, PlayerAvatar(avatarIndex: 5, picture: p, size: 48));
    expect(cache.requested, [p.path]);
    expect(_builtIn, findsOneWidget);
    expect(find.byType(Lottie), findsNothing);
  });

  testWidgets('an image picture is drawn from its file', (tester) async {
    final p = imagePicture();
    final file = File('${Directory.systemTemp.path}/pp_missing_test.png');
    cache.ready[p.path] = LoadedImagePicture(file);
    await pump(tester, PlayerAvatar(avatarIndex: 1, picture: p));
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as FileImage).file.path, file.path);
  });

  testWidgets('switching pictures resolves the new one', (tester) async {
    final a = lottiePicture('a');
    final b = imagePicture('b');
    cache.ready[a.path] = LoadedLottiePicture(testComposition());
    await pump(tester, PlayerAvatar(avatarIndex: 0, picture: a));
    expect(find.byType(Lottie), findsOneWidget);

    await pump(tester, PlayerAvatar(avatarIndex: 0, picture: b));
    expect(find.byType(Lottie), findsNothing);
    expect(_builtIn, findsOneWidget);
    expect(cache.requested.last, b.path);
  });
}
