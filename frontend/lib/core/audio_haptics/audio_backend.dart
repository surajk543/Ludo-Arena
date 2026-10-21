import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'sfx.dart';

/// Thrown by an [AudioBackend] when a sound's asset is not bundled. The
/// service then stops trying that sound (and logs it once).
class AudioAssetMissingException implements Exception {
  const AudioAssetMissingException(this.assetPath);

  final String assetPath;

  @override
  String toString() => 'AudioAssetMissingException(assets/$assetPath)';
}

/// The platform side of `AudioService`: plays effects and drives one music
/// player. Every method may throw; the service catches everything.
abstract interface class AudioBackend {
  /// Prepares [sfx] so its first play has no loading delay.
  Future<void> preload(Sfx sfx);

  /// Starts one copy of [sfx] at [volume] (0..1).
  Future<void> playSfx(Sfx sfx, double volume);

  /// Loads [track] into the music player (looping, volume 0, not playing).
  Future<void> musicLoad(MusicTrack track);

  Future<void> musicResume();

  Future<void> musicPause();

  Future<void> musicStop();

  Future<void> musicSetVolume(double volume);

  /// Loads [jingle] into the jingle player (not playing).
  Future<void> jingleLoad(Jingle jingle);

  /// Plays [jingle] once from the start at [volume] (0..1).
  Future<void> jinglePlay(Jingle jingle, double volume);

  Future<void> jingleStop();

  Future<void> dispose();
}

/// audioplayers implementation.
///
/// - Effects: one low-latency [AudioPool] per sound, sized to the sound's
///   voice limit. Low-latency pool players never report completion, so each
///   started copy is handed back to its pool after the sound's length (the
///   pool would otherwise create a new native player for every play).
/// - Music: one separate media-mode [AudioPlayer] (streams the AAC file).
/// - Never requests audio focus on Android; on iOS a mixing `playback`
///   session that keeps playing in silent mode — the user's own music keeps
///   playing too.
class AudioPlayersBackend implements AudioBackend {
  final Map<Sfx, Future<AudioPool>> _pools = {};
  final Set<Timer> _releases = {};
  AudioPlayer? _music;
  AudioPlayer? _jingle;
  Jingle? _jingleLoaded;
  Future<Set<String>>? _manifest;
  bool _contextSet = false;
  bool _disposed = false;

  /// The app's single iOS audio session (owner's rule, 22 Oct 2026: music
  /// and effects keep playing when the Ring/Silent switch is on silent; only
  /// the volume buttons and the in-app sound/music settings turn them down).
  /// `playback` ignores the silent switch; `mixWithOthers` keeps the user's
  /// own music playing alongside (only valid with playback, playAndRecord or
  /// multiRoute). Without the `audio` background mode, nothing plays once the
  /// app is in the background.
  static AudioContextIOS iosSession() => AudioContextIOS(
    category: AVAudioSessionCategory.playback,
    options: const {AVAudioSessionOptions.mixWithOthers},
  );

  /// Audio session for short game/UI effects.
  ///
  /// - iOS: [iosSession] (plays in silent mode, mixes with other apps).
  /// - Android: game/sonification usage without requesting audio focus, so
  ///   background music keeps playing (silent/vibrate mode never mutes
  ///   media on Android; the media volume does).
  static AudioContext sfxAudioContext() => AudioContext(
    iOS: iosSession(),
    android: const AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
  );

  /// Audio session for the lobby music: the same iOS session (iOS has one
  /// session per app, [iosSession]) and, on Android, game usage with music
  /// content and no audio focus — it never stops another app's music.
  static AudioContext musicAudioContext() => AudioContext(
    iOS: iosSession(),
    android: const AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
  );

  Future<void> _ensureContext() async {
    if (_contextSet) return;
    _contextSet = true;
    await AudioPlayer.global.setAudioContext(sfxAudioContext());
  }

  Future<void> _requireAsset(String assetPath) async {
    final assets = await (_manifest ??= AssetManifest.loadFromAssetBundle(
      rootBundle,
    ).then((m) => m.listAssets().toSet()));
    if (!assets.contains('assets/$assetPath')) {
      throw AudioAssetMissingException(assetPath);
    }
  }

  Future<AudioPool> _pool(Sfx sfx) {
    final existing = _pools[sfx];
    if (existing != null) return existing;
    final created = () async {
      await _ensureContext();
      await _requireAsset(sfx.assetPath);
      return AudioPool.create(
        source: AssetSource(sfx.assetPath),
        maxPlayers: sfx.voices,
        playerMode: PlayerMode.lowLatency,
        audioContext: sfxAudioContext(),
      );
    }();
    _pools[sfx] = created;
    // A failed load is retried on the next play (unless the asset is
    // missing: the service stops asking then).
    unawaited(
      created.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_pools[sfx], created)) _pools.remove(sfx);
        },
      ),
    );
    return created;
  }

  @override
  Future<void> preload(Sfx sfx) => _pool(sfx);

  @override
  Future<void> playSfx(Sfx sfx, double volume) async {
    final pool = await _pool(sfx);
    if (_disposed) return;
    final stop = await pool.start(volume: volume);
    late final Timer release;
    release = Timer(sfx.length + releaseDelay, () {
      _releases.remove(release);
      unawaited(stop().catchError((Object _) {}));
    });
    _releases.add(release);
  }

  /// Extra time before a finished copy goes back to its pool.
  static const Duration releaseDelay = sfxVoiceRelease;

  Future<AudioPlayer> _musicPlayer() async {
    final existing = _music;
    if (existing != null) return existing;
    final player = AudioPlayer(playerId: 'lobby_music');
    try {
      await player.setPlayerMode(PlayerMode.mediaPlayer);
      await player.setAudioContext(musicAudioContext());
      await player.setReleaseMode(ReleaseMode.loop);
    } catch (_) {
      await player.dispose();
      rethrow;
    }
    _music = player;
    return player;
  }

  @override
  Future<void> musicLoad(MusicTrack track) async {
    await _requireAsset(track.assetPath);
    final player = await _musicPlayer();
    await player.setVolume(0);
    await player.setSource(AssetSource(track.assetPath));
  }

  @override
  Future<void> musicResume() async {
    await _music?.resume();
  }

  @override
  Future<void> musicPause() async {
    await _music?.pause();
  }

  @override
  Future<void> musicStop() async {
    await _music?.stop();
  }

  @override
  Future<void> musicSetVolume(double volume) async {
    await _music?.setVolume(volume.clamp(0.0, 1.0));
  }

  Future<AudioPlayer> _jinglePlayer() async {
    final existing = _jingle;
    if (existing != null) return existing;
    final player = AudioPlayer(playerId: 'jingle');
    try {
      await player.setPlayerMode(PlayerMode.mediaPlayer);
      await player.setAudioContext(sfxAudioContext());
      await player.setReleaseMode(ReleaseMode.stop);
    } catch (_) {
      await player.dispose();
      rethrow;
    }
    _jingle = player;
    return player;
  }

  @override
  Future<void> jingleLoad(Jingle jingle) async {
    if (_jingleLoaded == jingle) return;
    await _requireAsset(jingle.assetPath);
    final player = await _jinglePlayer();
    await player.setSource(AssetSource(jingle.assetPath));
    _jingleLoaded = jingle;
  }

  @override
  Future<void> jinglePlay(Jingle jingle, double volume) async {
    await jingleLoad(jingle);
    final player = await _jinglePlayer();
    await player.setVolume(volume.clamp(0.0, 1.0));
    await player.seek(Duration.zero);
    await player.resume();
  }

  @override
  Future<void> jingleStop() async {
    await _jingle?.stop();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final t in _releases) {
      t.cancel();
    }
    _releases.clear();
    final pools = [..._pools.values];
    _pools.clear();
    for (final p in pools) {
      try {
        await (await p).dispose();
      } catch (_) {}
    }
    final music = _music;
    _music = null;
    try {
      await music?.dispose();
    } catch (_) {}
    final jingle = _jingle;
    _jingle = null;
    _jingleLoaded = null;
    try {
      await jingle?.dispose();
    } catch (_) {}
  }
}
