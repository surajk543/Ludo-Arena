import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'json_read.dart';
import 'message_types.dart';

const _deep = DeepCollectionEquality();

/// Value equality based on the JSON form (room objects are tiny; this keeps
/// equality exact and in sync with the wire format).
mixin JsonValueEquality {
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other.runtimeType == runtimeType &&
          other is JsonValueEquality &&
          _deep.equals(toJson(), other.toJson()));

  @override
  int get hashCode => _deep.hash(toJson());
}

/// Sentinel for nullable `copyWith` parameters.
const Object _unset = Object();

/// Catalogue asset formats (profile pictures and Store emotes).
abstract final class AssetFormats {
  static const String image = 'image';
  static const String lottie = 'lottie';
}

/// A downloadable catalogue object in the private asset bucket: a profile
/// picture or the art of a Store emote. [path] is an immutable object key
/// (new art = new path); the app downloads it once through a short-lived
/// signed URL (`POST /assets/sign`) and keeps it on disk (see
/// `core/assets/profile_picture_cache.dart`).
abstract interface class CatalogAsset {
  /// [AssetFormats.image] | [AssetFormats.lottie].
  String get format;

  /// Object key, e.g. `emotes/angry.json`.
  String get path;

  bool get isLottie;

  /// Whether [path] is a safe, relative key the app may store on disk.
  bool get hasSafePath;
}

final RegExp _assetSegment = RegExp(r'^[A-Za-z0-9._-]+$');

/// Whether [path] is a relative key under [prefix] (`<folder>/`) of only
/// `[A-Za-z0-9._-]` segments, without `.`/`..`, at most 255 characters.
bool isSafeAssetPath(String path, String prefix) {
  if (path.length > 255 || !path.startsWith(prefix)) return false;
  final segments = path.split('/');
  if (segments.length < 2) return false;
  for (final s in segments) {
    if (s.isEmpty || s == '.' || s == '..' || !_assetSegment.hasMatch(s)) {
      return false;
    }
  }
  return true;
}

/// A player's profile picture (`PlayerPicture`: `{"id","format","path"}`),
/// bought in the Store. `null` everywhere means the built-in avatar.
///
/// [path] is an immutable object key such as
/// `profile_pictures/lottie_animation/bear.json`; the app downloads it once
/// through a short-lived signed URL (`POST /assets/sign`) and keeps it on
/// disk (see `core/assets/profile_picture_cache.dart`).
@immutable
class PlayerPicture with JsonValueEquality implements CatalogAsset {
  const PlayerPicture({
    required this.id,
    required this.format,
    required this.path,
  });

  /// `pp_…` catalogue id.
  final String id;

  /// [formatImage] | [formatLottie].
  @override
  final String format;

  /// Object key under `profile_pictures/`.
  @override
  final String path;

  static const String formatImage = AssetFormats.image;
  static const String formatLottie = AssetFormats.lottie;

  @override
  bool get isLottie => format == formatLottie;

  @override
  bool get hasSafePath => isSafePath(path);

  /// Whether [path] is a safe, relative key the app may store on disk:
  /// `profile_pictures/…`, only `[A-Za-z0-9._-]` segments, no `.`/`..`.
  static bool isSafePath(String path) =>
      isSafeAssetPath(path, 'profile_pictures/');

  /// Parses a wire `picture`: null (the built-in avatar) for `null`, a
  /// missing field or anything malformed (unknown format, unsafe path).
  static PlayerPicture? tryParse(Object? raw) {
    final j = readMapOrNull(raw);
    if (j == null) return null;
    final id = readString(j['id']);
    final format = readString(j['format']);
    final path = readString(j['path']);
    if (id.isEmpty ||
        (format != formatImage && format != formatLottie) ||
        !isSafePath(path)) {
      return null;
    }
    return PlayerPicture(id: id, format: format, path: path);
  }

  @override
  Map<String, dynamic> toJson() => {'id': id, 'format': format, 'path': path};
}

/// The art of a Store emote (`chat.emote` `asset`: `{"path","format"}`).
/// Built-in emotes (`emote_wave`, …) are painted by the app and have none.
@immutable
class EmoteAsset with JsonValueEquality implements CatalogAsset {
  const EmoteAsset({required this.format, required this.path});

  /// [AssetFormats.lottie] | [AssetFormats.image].
  @override
  final String format;

  /// Object key under `emotes/`, e.g. `emotes/angry.json`.
  @override
  final String path;

  @override
  bool get isLottie => format == AssetFormats.lottie;

  @override
  bool get hasSafePath => isSafePath(path);

  /// Whether [path] is a safe, relative key under `emotes/`.
  static bool isSafePath(String path) => isSafeAssetPath(path, 'emotes/');

  /// Parses a wire `asset`: null for `null`, a missing field or anything
  /// malformed (unknown format, unsafe path).
  static EmoteAsset? tryParse(Object? raw) {
    final j = readMapOrNull(raw);
    if (j == null) return null;
    final format = readString(j['format']);
    final path = readString(j['path']);
    if ((format != AssetFormats.image && format != AssetFormats.lottie) ||
        !isSafePath(path)) {
      return null;
    }
    return EmoteAsset(format: format, path: path);
  }

  @override
  Map<String, dynamic> toJson() => {'path': path, 'format': format};
}

/// Cosmetics a player has equipped for this room (`players[].cosmetics`).
@immutable
class PlayerCosmetics with JsonValueEquality {
  const PlayerCosmetics({
    this.dice = 'dice_classic',
    this.token = 'token_classic',
    this.frame = 'frame_none',
    this.trail = 'trail_none',
    this.victory = 'victory_confetti',
  });

  final String dice;
  final String token;
  final String frame;
  final String trail;
  final String victory;

  factory PlayerCosmetics.fromJson(Map<String, dynamic> j) => PlayerCosmetics(
    dice: readString(j['dice'], 'dice_classic'),
    token: readString(j['token'], 'token_classic'),
    frame: readString(j['frame'], 'frame_none'),
    trail: readString(j['trail'], 'trail_none'),
    victory: readString(j['victory'], 'victory_confetti'),
  );

  @override
  Map<String, dynamic> toJson() => {
    'dice': dice,
    'token': token,
    'frame': frame,
    'trail': trail,
    'victory': victory,
  };
}

/// One seated player (`room.players[]`).
@immutable
class RoomPlayer with JsonValueEquality {
  const RoomPlayer({
    required this.seat,
    required this.uid,
    required this.name,
    this.avatar = 0,
    this.level = 1,
    this.title = 'title_rookie',
    this.cosmetics = const PlayerCosmetics(),
    this.picture,
    this.color = 'red',
    this.connected = true,
    this.bot = false,
    this.forfeited = false,
    this.forfeitWhy = '',
    this.strikes = 0,
  });

  final int seat;

  /// Opaque public player id (NOT the account id).
  final String uid;
  final String name;
  final int avatar;
  final int level;
  final String title;
  final PlayerCosmetics cosmetics;

  /// Profile picture worn in this room (null: the built-in [avatar]). Not
  /// part of the state hash.
  final PlayerPicture? picture;

  /// `red` | `green` | `yellow` | `blue`.
  final String color;
  final bool connected;

  /// Server-determined. Bots are never labelled in the UI (no badge or
  /// "bot" wording); they only get no Add friend / Report actions.
  final bool bot;
  final bool forfeited;

  /// Why a forfeited seat is out ([ForfeitReasons]: `left` | `timeouts`);
  /// empty while playing (and from older servers).
  final String forfeitWhy;

  /// Consecutive turn timeouts (server `MAX_STRIKES`, default
  /// [ForfeitReasons.defaultMaxStrikes], → forfeit).
  final int strikes;

  factory RoomPlayer.fromJson(Map<String, dynamic> j) => RoomPlayer(
    seat: readInt(j['seat']),
    uid: readString(j['uid']),
    name: readString(j['name']),
    avatar: readInt(j['avatar']),
    level: readInt(j['level'], 1),
    title: readString(j['title'], 'title_rookie'),
    cosmetics: PlayerCosmetics.fromJson(readMap(j['cosmetics'])),
    picture: PlayerPicture.tryParse(j['picture']),
    color: readString(j['color'], 'red'),
    connected: readBool(j['connected'], true),
    bot: readBool(j['bot']),
    forfeited: readBool(j['forfeited']),
    forfeitWhy: readString(j['forfeitWhy']),
    strikes: readInt(j['strikes']),
  );

  @override
  Map<String, dynamic> toJson() => {
    'seat': seat,
    'uid': uid,
    'name': name,
    'avatar': avatar,
    'level': level,
    'title': title,
    'cosmetics': cosmetics.toJson(),
    if (picture != null) 'picture': picture!.toJson(),
    'color': color,
    'connected': connected,
    'bot': bot,
    'forfeited': forfeited,
    if (forfeitWhy.isNotEmpty) 'forfeitWhy': forfeitWhy,
    'strikes': strikes,
  };

  RoomPlayer copyWith({
    bool? connected,
    bool? forfeited,
    String? forfeitWhy,
    int? strikes,
  }) => RoomPlayer(
    seat: seat,
    uid: uid,
    name: name,
    avatar: avatar,
    level: level,
    title: title,
    cosmetics: cosmetics,
    picture: picture,
    color: color,
    connected: connected ?? this.connected,
    bot: bot,
    forfeited: forfeited ?? this.forfeited,
    forfeitWhy: forfeitWhy ?? this.forfeitWhy,
    strikes: strikes ?? this.strikes,
  );
}

/// Whose turn it is and what they may do (`room.turn`).
@immutable
class TurnState with JsonValueEquality {
  const TurnState({
    this.seat = 0,
    this.phase = TurnPhases.none,
    this.turnSeq = 0,
    this.deadline = 0,
    this.dice = 0,
    this.legal = const [],
    this.sixStreak = 0,
  });

  final int seat;

  /// See [TurnPhases].
  final String phase;

  /// Must be echoed by `game.roll_dice` / `game.make_move`.
  final int turnSeq;

  /// Unix ms, server clock. Use `ServerClock.remainingUntil`.
  final int deadline;

  /// Last roll in this turn; 0 = none.
  final int dice;

  /// Ludo: legal token indices while `awaiting_move`.
  final List<int> legal;
  final int sixStreak;

  bool get awaitingRoll => phase == TurnPhases.awaitingRoll;
  bool get awaitingMove => phase == TurnPhases.awaitingMove;

  factory TurnState.fromJson(Map<String, dynamic> j) => TurnState(
    seat: readInt(j['seat']),
    phase: readString(j['phase'], TurnPhases.none),
    turnSeq: readInt(j['turnSeq']),
    deadline: readInt(j['deadline']),
    dice: readInt(j['dice']),
    legal: readIntList(j['legal']),
    sixStreak: readInt(j['sixStreak']),
  );

  @override
  Map<String, dynamic> toJson() => {
    'seat': seat,
    'phase': phase,
    'turnSeq': turnSeq,
    'deadline': deadline,
    'dice': dice,
    'legal': legal,
    'sixStreak': sixStreak,
  };

  TurnState copyWith({
    int? seat,
    String? phase,
    int? turnSeq,
    int? deadline,
    int? dice,
    List<int>? legal,
    int? sixStreak,
  }) => TurnState(
    seat: seat ?? this.seat,
    phase: phase ?? this.phase,
    turnSeq: turnSeq ?? this.turnSeq,
    deadline: deadline ?? this.deadline,
    dice: dice ?? this.dice,
    legal: legal == null ? this.legal : List<int>.unmodifiable(legal),
    sixStreak: sixStreak ?? this.sixStreak,
  );
}

/// Board state (`room.board`). Only the key for the room's game is present.
@immutable
class BoardState with JsonValueEquality {
  const BoardState({this.ludoTokens, this.snakesPositions});

  /// Ludo: `[seat][token]` progress (-1 base, 0..50 track, 51..55 home
  /// column, 56 home). See backend/docs/game-rules.md.
  final List<List<int>>? ludoTokens;

  /// Snakes & Ladders: `[seat]` square (0 = off board, 1..100).
  final List<int>? snakesPositions;

  factory BoardState.fromJson(Map<String, dynamic> j) => BoardState(
    ludoTokens: j['tokens'] is List
        ? List<List<int>>.unmodifiable(
            readList(j['tokens']).map((seat) => readIntList(seat)),
          )
        : null,
    snakesPositions: j['positions'] is List
        ? readIntList(j['positions'])
        : null,
  );

  @override
  Map<String, dynamic> toJson() => {
    if (ludoTokens != null) 'tokens': ludoTokens,
    if (snakesPositions != null) 'positions': snakesPositions,
  };

  BoardState withLudoTokens(List<List<int>> tokens) => BoardState(
    ludoTokens: List<List<int>>.unmodifiable(
      tokens.map((t) => List<int>.unmodifiable(t)),
    ),
    snakesPositions: snakesPositions,
  );

  BoardState withSnakesPositions(List<int> positions) => BoardState(
    ludoTokens: ludoTokens,
    snakesPositions: List<int>.unmodifiable(positions),
  );
}

/// `room.result` (present when `status == "finished"`).
@immutable
class RoomResult with JsonValueEquality {
  const RoomResult({
    required this.winnerSeat,
    this.reason = 'completed',
    this.placements = const [],
    this.payout = 0,
  });

  final int winnerSeat;

  /// `completed` | `forfeit`.
  final String reason;

  /// Seats in finishing order.
  final List<int> placements;

  /// Coins paid to the winner (0 when a bot was seated).
  final int payout;

  factory RoomResult.fromJson(Map<String, dynamic> j) => RoomResult(
    winnerSeat: readInt(j['winnerSeat'], -1),
    reason: readString(j['reason'], 'completed'),
    placements: readIntList(j['placements']),
    payout: readInt(j['payout']),
  );

  @override
  Map<String, dynamic> toJson() => {
    'winnerSeat': winnerSeat,
    'reason': reason,
    'placements': placements,
    'payout': payout,
  };
}

/// `room.rematch` (present when `status == "finished"`).
@immutable
class RematchState with JsonValueEquality {
  const RematchState({
    this.open = false,
    this.deadline = 0,
    this.accepted = const [],
    this.declined = const [],
  });

  final bool open;

  /// Unix ms, server clock.
  final int deadline;

  /// Seats that accepted / declined.
  final List<int> accepted;
  final List<int> declined;

  factory RematchState.fromJson(Map<String, dynamic> j) => RematchState(
    open: readBool(j['open']),
    deadline: readInt(j['deadline']),
    accepted: readIntList(j['accepted']),
    declined: readIntList(j['declined']),
  );

  @override
  Map<String, dynamic> toJson() => {
    'open': open,
    'deadline': deadline,
    'accepted': accepted,
    'declined': declined,
  };
}

/// Full room snapshot (`room` object, websocket-protocol.md §4).
@immutable
class RoomSnapshot with JsonValueEquality {
  const RoomSnapshot({
    required this.id,
    required this.v,
    required this.game,
    this.variant = GameVariants.classic,
    this.mode = RoomModes.public,
    this.allowBots = false,
    this.code,
    this.capacity = 4,
    this.status = RoomStatuses.lobby,
    this.hostSeat = -1,
    this.entryFee = 0,
    this.pot = 0,
    this.round = 1,
    this.fillDeadline = 0,
    this.players = const [],
    this.turn = const TurnState(),
    this.board = const BoardState(),
    this.result,
    this.rematch,
    this.h,
  });

  final String id;

  /// Monotonic state version (§3).
  final int v;

  /// [GameIds].
  final String game;

  /// [GameVariants].
  final String variant;

  /// [RoomModes].
  final String mode;
  final bool allowBots;

  /// Private rooms only (members see it). Never log or send to analytics.
  final String? code;
  final int capacity;

  /// [RoomStatuses].
  final String status;

  /// Private rooms; -1 for public.
  final int hostSeat;
  final int entryFee;
  final int pot;

  /// Increments on each rematch in the same room.
  final int round;

  /// Public lobby: unix ms when it starts/times out.
  final int fillDeadline;
  final List<RoomPlayer> players;
  final TurnState turn;
  final BoardState board;
  final RoomResult? result;
  final RematchState? rematch;

  /// State hash as sent by the server (snapshots carry it too).
  final int? h;

  bool get isLudo => game == GameIds.ludo;
  bool get isSnakes => game == GameIds.snakesLadders;
  bool get isLobby => status == RoomStatuses.lobby;
  bool get isPlaying => status == RoomStatuses.playing;
  bool get isFinished => status == RoomStatuses.finished;
  bool get isClosed => status == RoomStatuses.closed;
  bool get isPrivate => mode == RoomModes.private;
  bool get isPractice => mode == RoomModes.practice;
  bool get hasBots => players.any((p) => p.bot);

  RoomPlayer? playerAtSeat(int seat) =>
      players.firstWhereOrNull((p) => p.seat == seat);

  RoomPlayer? playerByUid(String? uid) =>
      uid == null ? null : players.firstWhereOrNull((p) => p.uid == uid);

  factory RoomSnapshot.fromJson(Map<String, dynamic> j) => RoomSnapshot(
    id: readString(j['id']),
    v: readInt(j['v']),
    game: readString(j['game'], GameIds.ludo),
    variant: readString(j['variant'], GameVariants.classic),
    mode: readString(j['mode'], RoomModes.public),
    allowBots: readBool(j['allowBots']),
    code: readStringOrNull(j['code']),
    capacity: readInt(j['capacity'], 4),
    status: readString(j['status'], RoomStatuses.lobby),
    hostSeat: readInt(j['hostSeat'], -1),
    entryFee: readInt(j['entryFee']),
    pot: readInt(j['pot']),
    round: readInt(j['round'], 1),
    fillDeadline: readInt(j['fillDeadline']),
    players: List<RoomPlayer>.unmodifiable(
      readList(j['players']).map((p) => RoomPlayer.fromJson(readMap(p))),
    ),
    turn: TurnState.fromJson(readMap(j['turn'])),
    board: BoardState.fromJson(readMap(j['board'])),
    result: readMapOrNull(j['result']) == null
        ? null
        : RoomResult.fromJson(readMap(j['result'])),
    rematch: readMapOrNull(j['rematch']) == null
        ? null
        : RematchState.fromJson(readMap(j['rematch'])),
    h: readIntOrNull(j['h']),
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'v': v,
    'game': game,
    'variant': variant,
    'mode': mode,
    'allowBots': allowBots,
    'code': ?code,
    'capacity': capacity,
    'status': status,
    'hostSeat': hostSeat,
    'entryFee': entryFee,
    'pot': pot,
    'round': round,
    'fillDeadline': fillDeadline,
    'players': [for (final p in players) p.toJson()],
    'turn': turn.toJson(),
    'board': board.toJson(),
    if (result != null) 'result': result!.toJson(),
    if (rematch != null) 'rematch': rematch!.toJson(),
    'h': ?h,
  };

  RoomSnapshot copyWith({
    int? v,
    String? status,
    List<RoomPlayer>? players,
    TurnState? turn,
    BoardState? board,
    Object? result = _unset,
    Object? rematch = _unset,
    Object? h = _unset,
  }) => RoomSnapshot(
    id: id,
    v: v ?? this.v,
    game: game,
    variant: variant,
    mode: mode,
    allowBots: allowBots,
    code: code,
    capacity: capacity,
    status: status ?? this.status,
    hostSeat: hostSeat,
    entryFee: entryFee,
    pot: pot,
    round: round,
    fillDeadline: fillDeadline,
    players: players == null
        ? this.players
        : List<RoomPlayer>.unmodifiable(players),
    turn: turn ?? this.turn,
    board: board ?? this.board,
    result: identical(result, _unset) ? this.result : result as RoomResult?,
    rematch: identical(rematch, _unset)
        ? this.rematch
        : rematch as RematchState?,
    h: identical(h, _unset) ? this.h : h as int?,
  );
}
