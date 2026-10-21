import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/audio_haptics/reduced_motion.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Loads the intro animation (tests inject a fake codec).
typedef IntroCodecLoader = Future<ui.Codec> Function();

/// The launch intro: the Sun Game Studio logo animation, played once on the
/// splash while the startup gate signs in underneath (`launchIntroPlayingProvider`).
///
/// The animation is the owner's logo video converted to an animated WebP
/// ([asset], 768 px, sound stripped) and played frame by frame from Flutter's
/// own codec: no video plugin, so nothing touches the audio session. Its
/// jingle plays through the app's audio service ([Jingle.studioIntro]), which
/// follows the Sound setting and volume, mixes with other apps and stops if
/// the app leaves the foreground.
///
/// Fades in over the splash background, holds each frame for its duration,
/// fades out over the last [fadeOut] and then calls [onFinished]. Skipped
/// (finished at once, no jingle) with reduced motion or when the animation
/// cannot be decoded; cut short when the app leaves the foreground or after
/// [maxDuration].
class StudioIntro extends ConsumerStatefulWidget {
  const StudioIntro({super.key, required this.onFinished, this.loadCodec});

  final VoidCallback onFinished;

  /// Defaults to decoding [asset].
  final IntroCodecLoader? loadCodec;

  static const String asset = 'assets/animations/studio_intro.webp';

  /// Fills the screen around the square animation (its edge colour, which
  /// drifts between #182B42 and #0C1F33; the edges are feathered into it).
  static const Color background = Color(0xFF102238);

  static const Duration fadeIn = Duration(milliseconds: 250);
  static const Duration fadeOut = Duration(milliseconds: 400);

  /// How long the first frame waits for the jingle to load; after that the
  /// animation starts anyway (the jingle then starts slightly late).
  static const Duration audioWait = Duration(milliseconds: 800);

  /// Safety net: the intro ends after this even if decoding stalls (the
  /// animation itself lasts 6.6 s).
  static const Duration maxDuration = Duration(seconds: 12);

  /// Feathered border, as a fraction of the square's side.
  static const double feather = 0.14;

  static Future<ui.Codec> loadAssetCodec() async {
    final data = await rootBundle.load(asset);
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    return ui.instantiateImageCodecFromBuffer(buffer);
  }

  @override
  ConsumerState<StudioIntro> createState() => _StudioIntroState();
}

class _StudioIntroState extends ConsumerState<StudioIntro>
    with WidgetsBindingObserver {
  ui.Image? _frame;
  ui.Codec? _codec;
  Timer? _safety;
  bool _visible = false;
  bool _started = false;
  bool _ending = false;
  bool _fadingOut = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reduceMotion) {
      _end(immediately: true);
      return;
    }
    _safety = Timer(StudioIntro.maxDuration, _end);
    unawaited(_play());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_ending) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      ref.read(audioServiceProvider).stopJingle();
      _end(immediately: true);
    }
  }

  Future<void> _play() async {
    final audio = ref.read(audioServiceProvider);
    final ui.Codec codec;
    try {
      final (loaded, _) = await (
        (widget.loadCodec ?? StudioIntro.loadAssetCodec)(),
        // Never throws; a slow load only means the jingle starts late.
        audio
            .preloadJingle(Jingle.studioIntro)
            .timeout(StudioIntro.audioWait, onTimeout: () {}),
      ).wait;
      codec = loaded;
    } catch (_) {
      // Undecodable animation: go straight to the app.
      _end(immediately: true);
      return;
    }
    if (!mounted || _ending) {
      codec.dispose();
      return;
    }
    _codec = codec;

    // `clock`: real time in the app, the fake clock in widget tests.
    final watch = clock.stopwatch();
    var due = Duration.zero;
    for (var i = 0; i < codec.frameCount; i++) {
      final ui.FrameInfo info;
      try {
        info = await codec.getNextFrame();
      } catch (_) {
        break;
      }
      if (i == 0) {
        watch.start();
        audio.playJingle(Jingle.studioIntro);
      } else {
        final wait = due - watch.elapsed;
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      if (!mounted || _ending) {
        info.image.dispose();
        return;
      }
      _show(info.image);
      due += info.duration;
      // The fade-out covers the last [fadeOut] of the animation (the
      // remaining frames are estimated at this frame's duration).
      final left =
          due + info.duration * (codec.frameCount - 1 - i) - watch.elapsed;
      if (left <= StudioIntro.fadeOut) _fadeOut();
    }
    final rest = due - watch.elapsed;
    if (rest > Duration.zero) await Future<void>.delayed(rest);
    _end();
  }

  void _show(ui.Image image) {
    final previous = _frame;
    setState(() {
      _frame = image;
      if (!_fadingOut) _visible = true;
    });
    // RawImage holds its own clone of what it painted.
    previous?.dispose();
  }

  void _fadeOut() {
    if (_fadingOut || !mounted) return;
    _fadingOut = true;
    setState(() => _visible = false);
  }

  /// Ends the intro: at once (skipped, or the fade-out already ran with the
  /// last frames) or after a fade-out.
  void _end({bool immediately = false}) {
    if (_ending) return;
    _ending = true;
    _safety?.cancel();
    if (immediately || _fadingOut || !mounted) {
      _finish();
      return;
    }
    _fadeOut();
    Future<void>.delayed(StudioIntro.fadeOut, _finish);
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    // Never synchronously: this can run during a build (reduced motion) and
    // the callback updates providers. A microtask also runs while the app
    // is in the background, when no frames are drawn.
    scheduleMicrotask(widget.onFinished);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _safety?.cancel();
    _frame?.dispose();
    _codec?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      image: true,
      label: AppLocalizations.of(context).gateStudioIntroLabel,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: _visible ? StudioIntro.fadeIn : StudioIntro.fadeOut,
        curve: Curves.easeOut,
        child: ColoredBox(
          color: StudioIntro.background,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = math.min(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              return Center(
                child: SizedBox.square(
                  dimension: side,
                  child: _Feathered(
                    child: RawImage(
                      image: _frame,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Fades the square's border into the background on all four sides, so its
/// edge never shows as a seam (the animation's edge colour drifts).
class _Feathered extends StatelessWidget {
  const _Feathered({required this.child});

  final Widget child;

  static ShaderMask _mask(Axis axis, Widget child) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (bounds) => LinearGradient(
      begin: axis == Axis.vertical ? Alignment.topCenter : Alignment.centerLeft,
      end: axis == Axis.vertical
          ? Alignment.bottomCenter
          : Alignment.centerRight,
      colors: const [
        Color(0x00000000),
        Color(0xFF000000),
        Color(0xFF000000),
        Color(0x00000000),
      ],
      stops: const [0, StudioIntro.feather, 1 - StudioIntro.feather, 1],
    ).createShader(bounds),
    child: child,
  );

  @override
  Widget build(BuildContext context) =>
      _mask(Axis.vertical, _mask(Axis.horizontal, child));
}
