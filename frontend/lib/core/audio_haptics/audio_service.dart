import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lifecycle/app_lifecycle.dart';
import '../settings/app_settings.dart';
import 'audio_backend.dart';
import 'sfx.dart';

export 'audio_backend.dart' show AudioAssetMissingException, AudioBackend;
export 'sfx.dart';

/// Monotonic time source (injectable for tests).
typedef AudioClock = Duration Function();

/// The app's one audio service: sound effects and the lobby music.
///
/// - Honors the Sound master switch and the effects / music volumes
///   ([applySettings], wired from Settings by [audioSettingsBinderProvider]);
///   final effect volume = effects volume × [Sfx.gain] × call volume.
/// - UI sounds of one gesture are coalesced ([SfxChannel.ui]): one tap → one
///   sound. Every sound has a cooldown and a voice limit, so bursts (token
///   steps) never pile up and a double event never doubles a sound.
/// - Music: one looping track at a time ([playMusic] / [stopMusic]) with
///   fades, paused while the app is in the background ([setForeground]).
/// - Never throws. A missing asset is logged once and then skipped.
class AudioService {
  AudioService({
    required this._backend,
    AudioClock? clock,
    this.musicFade = const Duration(milliseconds: 400),
    this.uiGestureWindow = const Duration(milliseconds: 150),
    void Function(String message)? log,
  }) : _clock = clock ?? _stopwatchClock(),
       _log = log ?? ((m) => debugPrint(m));

  static AudioClock _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  final AudioBackend _backend;
  final AudioClock _clock;
  final void Function(String message) _log;

  /// Fade-in / fade-out time of the music on transitions.
  final Duration musicFade;

  /// After a UI sound, a less (or equally) important UI sound within this
  /// window belongs to the same gesture and is dropped.
  final Duration uiGestureWindow;

  bool _enabled = true;
  double _sfxVolume = AppSettings.defaultSfxVolume;
  double _musicVolume = AppSettings.defaultMusicVolume;
  bool _foreground = true;
  bool _disposed = false;

  bool get enabled => _enabled;
  double get sfxVolume => _sfxVolume;
  double get musicVolume => _musicVolume;
  bool get isForeground => _foreground;

  /// Applies the Settings values (master switch and volumes 0..1).
  void applySettings({
    required bool enabled,
    required double sfxVolume,
    required double musicVolume,
  }) {
    _enabled = enabled;
    _sfxVolume = sfxVolume.clamp(0.0, 1.0);
    _musicVolume = musicVolume.clamp(0.0, 1.0);
    _syncMusic();
  }

  /// App lifecycle: effects are dropped, a jingle stops and the music pauses
  /// in the background; the music fades back in on return.
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) stopJingle();
    _syncMusic();
  }

  // ------------------------------------------------------------- jingles

  final Set<Jingle> _missingJingles = {};

  /// Loads [jingle] so [playJingle] starts it without delay. Never throws.
  Future<void> preloadJingle(Jingle jingle) async {
    if (_disposed || _missingJingles.contains(jingle)) return;
    try {
      await _backend.jingleLoad(jingle);
    } catch (e) {
      _jingleFailed(jingle, e);
    }
  }

  /// Plays [jingle] once at the effects volume × its gain. No-op when sound
  /// is off, the effects volume is zero or the app is in the background.
  void playJingle(Jingle jingle) {
    if (_disposed || !_enabled || !_foreground) return;
    if (_missingJingles.contains(jingle)) return;
    final v = (_sfxVolume * jingle.gain).clamp(0.0, 1.0);
    if (v <= 0) return;
    unawaited(
      Future<void>.sync(
        () => _backend.jinglePlay(jingle, v),
      ).catchError((Object e) => _jingleFailed(jingle, e)),
    );
  }

  /// Stops a playing jingle (e.g. the launch intro cut short).
  void stopJingle() {
    if (_disposed) return;
    unawaited(_backend.jingleStop().catchError((Object _) {}));
  }

  void _jingleFailed(Jingle jingle, Object error) {
    if (error is AudioAssetMissingException) _missingJingles.add(jingle);
    _log('audio: ${jingle.file} failed ($error)');
  }

  // ------------------------------------------------------------- effects

  final Map<Object, Duration> _lastStart = {};
  final Map<Sfx, ListQueue<Duration>> _voices = {};
  final Set<Sfx> _missing = {};
  final Set<Sfx> _logged = {};

  Sfx? _pendingUi;
  double _pendingUiVolume = 1;
  bool _uiFlushScheduled = false;
  Duration? _uiPlayedAt;
  int _uiPlayedPriority = -1;

  /// Fire-and-forget. No-op when sound is off, the app is in the background,
  /// the sound is cooling down or already playing on all its voices.
  void play(Sfx sfx, {double volume = 1.0}) {
    if (!_canPlay(sfx)) return;
    if (sfx.channel == SfxChannel.ui) {
      _requestUi(sfx, volume);
    } else {
      _start(sfx, volume, _clock());
    }
  }

  bool _canPlay(Sfx sfx) =>
      !_disposed && _enabled && _foreground && !_missing.contains(sfx);

  void _requestUi(Sfx sfx, double volume) {
    final pending = _pendingUi;
    if (pending == null || sfx.priority > pending.priority) {
      _pendingUi = sfx;
      _pendingUiVolume = volume;
    }
    if (_uiFlushScheduled) return;
    _uiFlushScheduled = true;
    // Everything a tap triggers synchronously (button click, sheet opening,
    // navigation) runs before this microtask: only the winner plays.
    scheduleMicrotask(_flushUi);
  }

  void _flushUi() {
    _uiFlushScheduled = false;
    final sfx = _pendingUi;
    _pendingUi = null;
    if (sfx == null || !_canPlay(sfx)) return;
    final now = _clock();
    final last = _uiPlayedAt;
    if (last != null &&
        now - last < uiGestureWindow &&
        sfx.priority <= _uiPlayedPriority) {
      return;
    }
    if (_start(sfx, _pendingUiVolume, now)) {
      _uiPlayedAt = now;
      _uiPlayedPriority = sfx.priority;
    }
  }

  bool _start(Sfx sfx, double volume, Duration now) {
    final key = sfx.group ?? sfx;
    final last = _lastStart[key];
    if (last != null && now - last < sfx.cooldown) return false;
    final voices = _voices.putIfAbsent(sfx, ListQueue<Duration>.new);
    final busy = sfx.length + sfxVoiceRelease;
    while (voices.isNotEmpty && now - voices.first >= busy) {
      voices.removeFirst();
    }
    if (voices.length >= sfx.voices) return false;
    final v = (_sfxVolume * sfx.gain * volume).clamp(0.0, 1.0);
    if (v <= 0) return false;
    _lastStart[key] = now;
    voices.addLast(now);
    if (sfx.channel == SfxChannel.event) {
      // A reward / match-start moment owns the next instant: the dialog or
      // sheet it opens stays quiet (an error still sounds).
      final within =
          _uiPlayedAt != null && now - _uiPlayedAt! < uiGestureWindow;
      _uiPlayedAt = now;
      _uiPlayedPriority = math.max(within ? _uiPlayedPriority : -1, 3);
    }
    unawaited(
      Future<void>.sync(
        () => _backend.playSfx(sfx, v),
      ).catchError((Object e) => _sfxFailed(sfx, e)),
    );
    return true;
  }

  void _sfxFailed(Sfx sfx, Object error) {
    if (error is AudioAssetMissingException) _missing.add(sfx);
    // A missing codec or audio focus loss must never break gameplay.
    if (_logged.add(sfx)) _log('audio: ${sfx.file} failed ($error)');
  }

  /// Pre-loads the most frequent effects (call once after the first frame).
  Future<void> warmUp() async {
    for (final s in Sfx.values.where((s) => s.preload)) {
      try {
        await _backend.preload(s);
      } catch (e) {
        _sfxFailed(s, e);
      }
    }
  }

  // --------------------------------------------------------------- music

  MusicTrack? _wanted;
  MusicTrack? _loaded;
  bool _musicPlaying = false;
  double _musicLevel = 0;
  Timer? _fade;
  final Set<MusicTrack> _missingTracks = {};
  final Set<MusicTrack> _loggedTracks = {};
  bool _reconciling = false;
  bool _dirty = false;

  /// The track the app wants (null: none).
  MusicTrack? get musicTrack => _wanted;

  /// True while the music player runs (including fades).
  bool get isMusicPlaying => _musicPlaying;

  /// Current music player volume (moves during fades).
  double get musicLevel => _musicLevel;

  /// Loops [track] (fading in) whenever sound is on, the music volume is
  /// above zero and the app is in the foreground.
  void playMusic(MusicTrack track) {
    if (_wanted == track) return;
    _wanted = track;
    _syncMusic();
  }

  /// Fades the music out and pauses it.
  void stopMusic() {
    if (_wanted == null) return;
    _wanted = null;
    _syncMusic();
  }

  bool get _musicAudible {
    final track = _wanted;
    return track != null &&
        !_disposed &&
        _enabled &&
        _foreground &&
        _musicVolume > 0 &&
        !_missingTracks.contains(track);
  }

  void _syncMusic() => unawaited(_reconcile());

  /// Serializes the asynchronous player operations; state changes made
  /// meanwhile are picked up by another pass.
  Future<void> _reconcile() async {
    if (_reconciling) {
      _dirty = true;
      return;
    }
    _reconciling = true;
    try {
      do {
        _dirty = false;
        await _reconcileOnce();
      } while (_dirty && !_disposed);
    } finally {
      _reconciling = false;
    }
  }

  Future<void> _reconcileOnce() async {
    final want = _musicAudible ? _wanted : null;
    if (want == null) {
      if (!_musicPlaying) return;
      if (_foreground && !_disposed && musicFade > Duration.zero) {
        _fadeTo(0, musicFade, onDone: _pauseIfSilent);
      } else {
        _cancelFade();
        _setLevel(0);
        _musicPlaying = false;
        await _guard(_backend.musicPause);
      }
      return;
    }
    if (_loaded != want) {
      if (_loaded != null) {
        _cancelFade();
        _setLevel(0);
        _musicPlaying = false;
        _loaded = null;
        await _guard(_backend.musicStop);
      }
      try {
        await _backend.musicLoad(want);
      } catch (e) {
        // Not bundled: never asked again. Other failures are retried on the
        // next change (e.g. the next return to the lobby).
        if (e is AudioAssetMissingException) _missingTracks.add(want);
        if (_loggedTracks.add(want)) {
          _log('audio: music ${want.assetPath} unavailable ($e)');
        }
        return;
      }
      _loaded = want;
      _musicLevel = 0;
      if (_wanted != want || !_musicAudible) {
        _dirty = true;
        return;
      }
    }
    if (!_musicPlaying) {
      _cancelFade();
      _setLevel(0);
      _musicPlaying = true;
      await _guard(_backend.musicResume);
    }
    // Transitions fade; a volume change while playing applies at once.
    final transition = _fade != null || _musicLevel == 0;
    _fadeTo(_musicVolume, transition ? musicFade : Duration.zero);
  }

  void _fadeTo(double target, Duration duration, {VoidCallback? onDone}) {
    _cancelFade();
    if (duration <= Duration.zero || (target - _musicLevel).abs() < 0.001) {
      _setLevel(target);
      onDone?.call();
      return;
    }
    const step = Duration(milliseconds: 40);
    final steps = math.max(1, duration.inMilliseconds ~/ step.inMilliseconds);
    final from = _musicLevel;
    var i = 0;
    _fade = Timer.periodic(step, (timer) {
      i++;
      final t = math.min(1.0, i / steps);
      _setLevel(from + (target - from) * t);
      if (i >= steps) {
        timer.cancel();
        _fade = null;
        onDone?.call();
      }
    });
  }

  void _cancelFade() {
    _fade?.cancel();
    _fade = null;
  }

  void _setLevel(double v) {
    _musicLevel = v;
    unawaited(_guard(() => _backend.musicSetVolume(v)));
  }

  void _pauseIfSilent() {
    if (_musicAudible || !_musicPlaying) return;
    _musicPlaying = false;
    unawaited(_guard(_backend.musicPause));
  }

  Future<void> _guard(Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      _log('audio: music player error ($e)');
    }
  }

  // ------------------------------------------------------------- dispose

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelFade();
    _pendingUi = null;
    try {
      await _backend.dispose();
    } catch (_) {}
  }
}

/// Records what an [AudioService] asked the platform to do (tests, previews).
class RecordingAudioBackend implements AudioBackend {
  RecordingAudioBackend({this.missingAssets = const {}});

  /// Asset paths (relative to `assets/`) that behave as not bundled.
  final Set<String> missingAssets;

  final List<Sfx> played = [];
  final List<double> volumes = [];
  final List<Sfx> preloaded = [];

  /// Music player calls in order, e.g. `load:lobby`, `resume`, `pause`.
  final List<String> musicCalls = [];

  /// Jingle player calls in order: `load:studioIntro`, `play:studioIntro`,
  /// `stop`.
  final List<String> jingleCalls = [];
  final List<double> jingleVolumes = [];
  final List<double> musicVolumes = [];
  bool disposed = false;

  @override
  Future<void> preload(Sfx sfx) async {
    if (missingAssets.contains(sfx.assetPath)) {
      throw AudioAssetMissingException(sfx.assetPath);
    }
    preloaded.add(sfx);
  }

  @override
  Future<void> playSfx(Sfx sfx, double volume) async {
    if (missingAssets.contains(sfx.assetPath)) {
      throw AudioAssetMissingException(sfx.assetPath);
    }
    played.add(sfx);
    volumes.add(volume);
  }

  @override
  Future<void> musicLoad(MusicTrack track) async {
    if (missingAssets.contains(track.assetPath)) {
      throw AudioAssetMissingException(track.assetPath);
    }
    musicCalls.add('load:${track.name}');
  }

  @override
  Future<void> musicResume() async => musicCalls.add('resume');

  @override
  Future<void> musicPause() async => musicCalls.add('pause');

  @override
  Future<void> musicStop() async => musicCalls.add('stop');

  @override
  Future<void> musicSetVolume(double volume) async => musicVolumes.add(volume);

  @override
  Future<void> jingleLoad(Jingle jingle) async {
    if (missingAssets.contains(jingle.assetPath)) {
      throw AudioAssetMissingException(jingle.assetPath);
    }
    jingleCalls.add('load:${jingle.name}');
  }

  @override
  Future<void> jinglePlay(Jingle jingle, double volume) async {
    if (missingAssets.contains(jingle.assetPath)) {
      throw AudioAssetMissingException(jingle.assetPath);
    }
    jingleCalls.add('play:${jingle.name}');
    jingleVolumes.add(volume);
  }

  @override
  Future<void> jingleStop() async => jingleCalls.add('stop');

  @override
  Future<void> dispose() async => disposed = true;
}

/// Silent [AudioService] for tests and previews: the full policy (mute,
/// volumes, gesture coalescing, cooldowns, music state) with a
/// [RecordingAudioBackend] instead of the platform.
///
/// Time defaults to the test binding's frame clock, so it only advances with
/// `tester.pump(duration)`: pump past [AudioService.uiGestureWindow] between
/// two separate taps. Music fades are instant by default (no timers).
class SilentAudioService extends AudioService {
  SilentAudioService({
    AudioClock? clock,
    Duration musicFade = Duration.zero,
    Set<String> missingAssets = const {},
    List<String>? log,
  }) : this._(
         RecordingAudioBackend(missingAssets: missingAssets),
         clock,
         musicFade,
         log,
       );

  SilentAudioService._(
    this.recorder,
    AudioClock? clock,
    Duration musicFade,
    List<String>? log,
  ) : super(
        backend: recorder,
        clock: clock ?? _frameClock(),
        musicFade: musicFade,
        log: log == null ? (_) {} : log.add,
      );

  final RecordingAudioBackend recorder;

  /// Effects that reached the (silent) player, in order.
  List<Sfx> get played => recorder.played;

  /// Final volumes of [played].
  List<double> get volumes => recorder.volumes;

  List<String> get musicCalls => recorder.musicCalls;

  /// Jingle player calls (see [RecordingAudioBackend.jingleCalls]).
  List<String> get jingleCalls => recorder.jingleCalls;

  static AudioClock _frameClock() {
    final fallback = Stopwatch()..start();
    return () {
      try {
        return SchedulerBinding.instance.currentSystemFrameTimeStamp;
      } catch (_) {
        return fallback.elapsed;
      }
    };
  }
}

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService(backend: AudioPlayersBackend());
  ref.onDispose(service.dispose);
  return service;
});

/// Keeps [audioServiceProvider] in sync with Settings (master switch,
/// volumes — applied live) and the app lifecycle. Watched by the root
/// widget.
final audioSettingsBinderProvider = Provider<void>((ref) {
  final audio = ref.watch(audioServiceProvider);
  void apply(AppSettings s) => audio.applySettings(
    enabled: s.soundEnabled,
    sfxVolume: s.sfxVolume,
    musicVolume: s.musicVolume,
  );
  ref.listen<AppSettings>(
    settingsControllerProvider,
    (_, next) => apply(next),
    fireImmediately: true,
  );
  final lifecycle = ref.watch(appLifecycleProvider);
  audio.setForeground(lifecycle.isForeground);
  final sub = lifecycle.changes.listen(
    (s) => audio.setForeground(s == AppLifecycleState.resumed),
  );
  ref.onDispose(sub.cancel);
});

/// The [AudioService] for widgets without a `WidgetRef` (stateless widgets,
/// static helpers); null outside a `ProviderScope`.
AudioService? audioServiceOf(BuildContext context) {
  try {
    return ProviderScope.containerOf(
      context,
      listen: false,
    ).read(audioServiceProvider);
  } catch (_) {
    return null;
  }
}

/// Plays [sfx] via [audioServiceOf]; no-op outside a `ProviderScope`.
void playUiSound(BuildContext context, Sfx sfx, {double volume = 1.0}) =>
    audioServiceOf(context)?.play(sfx, volume: volume);
