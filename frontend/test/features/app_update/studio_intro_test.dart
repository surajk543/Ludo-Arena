import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/audio_haptics/audio_service.dart';
import 'package:ludo_arena/core/audio_haptics/reduced_motion.dart';
import 'package:ludo_arena/features/app_update/presentation/studio_intro.dart';

import '../../helpers/harness.dart';
import '../../helpers/screen_harness.dart';

ui.Image _image() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFFFFAA00),
  );
  return recorder.endRecording().toImageSync(4, 4);
}

class _Frame implements ui.FrameInfo {
  _Frame(this.image, this.duration);

  @override
  final ui.Image image;

  @override
  final Duration duration;
}

/// [frames] frames of 100 ms; [stallAt] never delivers that frame.
class _FakeCodec implements ui.Codec {
  _FakeCodec({required this.frames, this.stallAt});

  final int frames;
  final int? stallAt;
  int delivered = 0;
  bool disposed = false;

  @override
  int get frameCount => frames;

  @override
  int get repetitionCount => 0;

  @override
  Future<ui.FrameInfo> getNextFrame() {
    if (delivered == stallAt) return Completer<ui.FrameInfo>().future;
    delivered++;
    return Future.value(_Frame(_image(), const Duration(milliseconds: 100)));
  }

  @override
  void dispose() => disposed = true;
}

void main() {
  late TestEnv env;
  late int finished;

  setUp(() async {
    env = await TestEnv.create();
    finished = 0;
  });

  Future<void> pumpIntro(
    WidgetTester tester, {
    required bool reduceMotion,
    IntroCodecLoader? loader,
  }) async {
    await pumpScreen(
      tester,
      env,
      ReducedMotion(
        reduce: reduceMotion,
        child: StudioIntro(onFinished: () => finished++, loadCodec: loader),
      ),
    );
  }

  double opacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(StudioIntro),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  testWidgets('plays every frame for its duration, starts the jingle with '
      'the first one, fades out over the last frames and finishes once', (
    tester,
  ) async {
    // 20 frames × 100 ms = 2 s; the fade-out starts at 1.6 s.
    final codec = _FakeCodec(frames: 20);
    // pumpScreen itself runs ~600 ms of the animation.
    await pumpIntro(tester, reduceMotion: false, loader: () async => codec);
    expect(codec.delivered, inInclusiveRange(6, 8));
    expect(env.audio.jingleCalls, ['load:studioIntro', 'play:studioIntro']);
    expect(opacity(tester), 1);
    expect(find.bySemanticsLabel('Sun Game Studio'), findsOneWidget);

    // ~1.3 s: frames keep coming at their own pace.
    await tester.pump(const Duration(milliseconds: 700));
    expect(codec.delivered, inInclusiveRange(13, 15));
    expect(opacity(tester), 1);
    expect(finished, 0);

    // ~1.7 s: fading out while the last frames play.
    await tester.pump(const Duration(milliseconds: 400));
    expect(opacity(tester), 0);
    expect(finished, 0);

    // ~2.1 s: every frame shown, the intro has ended.
    await tester.pump(const Duration(milliseconds: 400));
    expect(codec.delivered, 20);
    expect(finished, 1);
    expect(env.audio.jingleCalls, ['load:studioIntro', 'play:studioIntro']);

    await tester.pump(const Duration(seconds: 15));
    expect(finished, 1);
  });

  testWidgets('reduced motion: finishes at once, no animation, no jingle', (
    tester,
  ) async {
    var loaded = false;
    await pumpIntro(
      tester,
      reduceMotion: true,
      loader: () async {
        loaded = true;
        return _FakeCodec(frames: 3);
      },
    );
    await tester.pump();
    expect(finished, 1);
    expect(loaded, isFalse);
    expect(env.audio.jingleCalls, isEmpty);
  });

  testWidgets('an animation that cannot be decoded finishes at once', (
    tester,
  ) async {
    await pumpIntro(
      tester,
      reduceMotion: false,
      loader: () async => throw Exception('bad webp'),
    );
    await tester.pump();
    expect(finished, 1);
    expect(env.audio.jingleCalls, isNot(contains('play:studioIntro')));
  });

  testWidgets('leaving the foreground ends the intro and stops the jingle', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await pumpIntro(
      tester,
      reduceMotion: false,
      loader: () async => _FakeCodec(frames: 50),
    );
    expect(finished, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(finished, 1);
    expect(env.audio.jingleCalls.last, 'stop');
    // The frame loop notices on its next tick and stops.
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('a stalled decode still ends after maxDuration', (tester) async {
    final codec = _FakeCodec(frames: 50, stallAt: 3);
    await pumpIntro(tester, reduceMotion: false, loader: () async => codec);
    await tester.pump(const Duration(seconds: 5));
    expect(finished, 0);
    await tester.pump(StudioIntro.maxDuration);
    await tester.pump(StudioIntro.fadeOut);
    await tester.pump();
    expect(finished, 1);
  });

  testWidgets('the shipped animation decodes: 158 frames of ~42 ms, 768 px', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final codec = await StudioIntro.loadAssetCodec();
      expect(codec.frameCount, 158);
      final first = await codec.getNextFrame();
      expect(first.image.width, 768);
      expect(first.image.height, 768);
      expect(first.duration.inMilliseconds, inInclusiveRange(40, 42));
      first.image.dispose();
      codec.dispose();
    });
  });

  test('the jingle lasts as long as the animation (158 frames × 42 ms)', () {
    expect(
      (Jingle.studioIntro.length.inMilliseconds - 158 * 42).abs(),
      lessThan(50),
    );
  });
}
