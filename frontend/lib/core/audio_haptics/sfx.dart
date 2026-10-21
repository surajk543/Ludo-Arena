/// How a sound effect is scheduled by `AudioService`.
enum SfxChannel {
  /// Interface feedback (taps, tabs, sheets, errors). The requests of one
  /// gesture are coalesced: only the most important one plays, and a less
  /// important one right after it (e.g. a sheet's close sound after the
  /// button that closed it) is dropped. One tap → one sound.
  ui,

  /// Board / dice feedback driven by server-confirmed events.
  game,

  /// Server-confirmed moments outside the board (match start, rewards,
  /// level-ups, notifications).
  event,
}

/// Sound effects shipped as 16-bit PCM mono WAV under
/// `assets/audio/sfx/<file>.wav` (imported from Kenney's CC0 packs by
/// `tool/import_kenney_audio.sh`; see `assets/audio/ASSET_LICENSES.md`).
///
/// [gain] is the per-sound mix level (final volume = effects volume × gain ×
/// call volume). [length] is the file's duration (checked by a test) and,
/// with [voices], bounds how many copies may overlap. [cooldown] is the
/// minimum time between two starts of the sound — or of any sound in the same
/// [group].
enum Sfx {
  // ------------------------------------------------------------------ UI
  uiTap('ui_tap', SfxChannel.ui, gain: 0.8, priority: 1, length: 40),
  uiTab('ui_tab', SfxChannel.ui, gain: 0.8, priority: 1, length: 40),
  uiToggle('ui_toggle', SfxChannel.ui, gain: 0.8, priority: 1, length: 97),

  /// Volume slider preview (throttled by the gesture window).
  uiTick('ui_tick', SfxChannel.ui, gain: 0.7, priority: 0, length: 55),
  uiOpen('ui_open', SfxChannel.ui, gain: 0.7, priority: 2, length: 206),
  uiClose('ui_close', SfxChannel.ui, gain: 0.6, priority: 1, length: 200),

  /// A confirmed action (e.g. an item equipped).
  uiConfirm('ui_confirm', SfxChannel.ui, gain: 0.8, priority: 3, length: 317),

  /// A failed action (error / warning toast). Subtle.
  uiError('ui_error', SfxChannel.ui, gain: 0.6, priority: 4, length: 104),

  /// Play / Quick Play / Find match / Start.
  lobbyPlay('lobby_play', SfxChannel.ui, gain: 0.9, priority: 3, length: 368),

  // --------------------------------------------------------------- events
  notification(
    'notification',
    SfxChannel.event,
    gain: 0.7,
    cooldownMs: 1500,
    length: 276,
  ),

  /// The server started the match (match found / host started / practice).
  matchStart(
    'match_start',
    SfxChannel.event,
    gain: 0.85,
    cooldownMs: 2000,
    length: 455,
  ),
  coin(
    'coin',
    SfxChannel.event,
    gain: 0.8,
    group: 'reward',
    cooldownMs: 1000,
    length: 349,
  ),
  rewardClaim(
    'reward_claim',
    SfxChannel.event,
    gain: 0.85,
    group: 'reward',
    cooldownMs: 1000,
    length: 776,
  ),
  purchase(
    'purchase',
    SfxChannel.event,
    gain: 0.8,
    group: 'reward',
    cooldownMs: 1000,
    length: 403,
  ),
  levelUp(
    'level_up',
    SfxChannel.event,
    gain: 0.9,
    cooldownMs: 2000,
    length: 1387,
  ),

  // ----------------------------------------------------------------- game
  chatPop('chat_pop', SfxChannel.game, gain: 0.6, cooldownMs: 120, length: 188),

  /// The local player's roll (never for other players).
  diceRoll(
    'dice_roll',
    SfxChannel.game,
    gain: 0.9,
    cooldownMs: 300,
    length: 370,
  ),

  /// A die settles on its server value (every roll; softer for others).
  diceLand(
    'dice_land',
    SfxChannel.game,
    gain: 0.75,
    cooldownMs: 100,
    length: 174,
  ),
  tokenSelect(
    'token_select',
    SfxChannel.game,
    gain: 0.7,
    cooldownMs: 100,
    length: 134,
  ),

  /// One square of a move. Soft; bursts are capped by [cooldown]/[voices].
  tokenStep(
    'token_step',
    SfxChannel.game,
    gain: 0.5,
    cooldownMs: 55,
    voices: 3,
    length: 135,
  ),
  tokenLeaveBase('token_leave_base', SfxChannel.game, gain: 0.8, length: 177),
  tokenSafe('token_safe', SfxChannel.game, gain: 0.7, length: 121),
  tokenHomePath('token_home_path', SfxChannel.game, gain: 0.75, length: 209),

  /// A capture heard by the attacker (and, softer, by onlookers).
  tokenCapture('token_capture', SfxChannel.game, gain: 0.95, length: 325),

  /// The local player's token was captured (softer, descending).
  tokenCaptured('token_captured', SfxChannel.game, gain: 0.8, length: 364),
  tokenHome(
    'token_home',
    SfxChannel.game,
    gain: 0.9,
    cooldownMs: 300,
    length: 560,
  ),
  turnMine(
    'turn_mine',
    SfxChannel.game,
    gain: 0.75,
    cooldownMs: 600,
    length: 290,
  ),
  snakeSlide('snake_slide', SfxChannel.game, gain: 0.85, length: 986),
  ladderClimb('ladder_climb', SfxChannel.game, gain: 0.85, length: 945),
  win('win', SfxChannel.game, gain: 1.0, cooldownMs: 2000, length: 909),
  lose('lose', SfxChannel.game, gain: 0.8, cooldownMs: 2000, length: 788);

  const Sfx(
    this.file,
    this.channel, {
    required this.gain,
    required int length,
    this.priority = 0,
    this._cooldownMs = 40,
    this.voices = 2,
    this.group,
  }) : _lengthMs = length;

  /// File name (without extension) under `assets/audio/sfx/`.
  final String file;
  final SfxChannel channel;

  /// Mix level 0..1.
  final double gain;

  /// Within one UI gesture the highest priority wins.
  final int priority;

  /// Maximum overlapping copies.
  final int voices;

  /// Sounds sharing a cooldown (e.g. a reward claim and the coin update the
  /// server sends right after it).
  final String? group;

  final int _cooldownMs;
  final int _lengthMs;

  Duration get cooldown => Duration(milliseconds: _cooldownMs);

  /// Approximate file duration.
  Duration get length => Duration(milliseconds: _lengthMs);

  /// Path relative to `assets/` (audioplayers' AssetSource prefix).
  String get assetPath => 'audio/sfx/$file.wav';

  /// Pre-loaded at startup (the most frequent effects).
  bool get preload => const {
    Sfx.uiTap,
    Sfx.uiTab,
    Sfx.uiOpen,
    Sfx.uiClose,
    Sfx.diceRoll,
    Sfx.diceLand,
    Sfx.tokenSelect,
    Sfx.tokenStep,
    Sfx.turnMine,
  }.contains(this);
}

/// A started effect counts as playing for its length plus this margin (the
/// backend hands the player back to its pool then).
const Duration sfxVoiceRelease = Duration(milliseconds: 120);

/// Background music tracks (`assets/audio/music/`).
enum MusicTrack {
  /// Loops on the lobby / meta screens (never during a match).
  lobby('lobby_loop.m4a');

  const MusicTrack(this.file);

  final String file;

  /// Path relative to `assets/`.
  String get assetPath => 'audio/music/$file';
}
