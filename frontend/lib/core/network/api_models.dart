import 'package:flutter/foundation.dart';

int _int(Object? v, [int fallback = 0]) => switch (v) {
  int i => i,
  num n => n.toInt(),
  String s => int.tryParse(s) ?? fallback,
  _ => fallback,
};

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};

/// Equipped cosmetics (`User.loadout`, `GET /collection` → `loadout`).
@immutable
class Loadout {
  const Loadout({
    this.dice = 'dice_classic',
    this.token = 'token_classic',
    this.ludoBoard = 'ludo_board_classic',
    this.snakesBoard = 'snakes_board_classic',
    this.frame = 'frame_none',
    this.title = 'title_rookie',
    this.victory = 'victory_confetti',
    this.trail = 'trail_none',
  });

  final String dice;
  final String token;
  final String ludoBoard;
  final String snakesBoard;
  final String frame;
  final String title;
  final String victory;
  final String trail;

  factory Loadout.fromJson(Map<String, dynamic> j) => Loadout(
    dice: _str(j['dice'], 'dice_classic'),
    token: _str(j['token'], 'token_classic'),
    ludoBoard: _str(j['ludo_board'], 'ludo_board_classic'),
    snakesBoard: _str(j['snakes_board'], 'snakes_board_classic'),
    frame: _str(j['frame'], 'frame_none'),
    title: _str(j['title'], 'title_rookie'),
    victory: _str(j['victory'], 'victory_confetti'),
    trail: _str(j['trail'], 'trail_none'),
  );

  Map<String, dynamic> toJson() => {
    'dice': dice,
    'token': token,
    'ludo_board': ludoBoard,
    'snakes_board': snakesBoard,
    'frame': frame,
    'title': title,
    'victory': victory,
    'trail': trail,
  };

  /// Value of an equip slot by its protocol name.
  String? slot(String name) => toJson()[name] as String?;

  @override
  bool operator ==(Object other) =>
      other is Loadout &&
      other.dice == dice &&
      other.token == token &&
      other.ludoBoard == ludoBoard &&
      other.snakesBoard == snakesBoard &&
      other.frame == frame &&
      other.title == title &&
      other.victory == victory &&
      other.trail == trail;

  @override
  int get hashCode => Object.hash(
    dice,
    token,
    ludoBoard,
    snakesBoard,
    frame,
    title,
    victory,
    trail,
  );
}

/// Identity providers that can be linked to an account.
enum LinkedProvider {
  guest,
  google,
  facebook,
  apple;

  static LinkedProvider? parse(String raw) {
    for (final p in values) {
      if (p.name == raw) return p;
    }
    return null;
  }
}

/// `User` object (only ever sent to its owner).
@immutable
class User {
  const User({
    required this.id,
    required this.uid,
    required this.actorType,
    required this.displayName,
    required this.avatar,
    required this.isGuest,
    required this.linkedProviders,
    required this.level,
    required this.xp,
    required this.levelXp,
    required this.nextLevelXp,
    required this.title,
    required this.loadout,
  });

  /// Internal account id. Never shown, logged, or sent to analytics.
  final String id;

  /// Public id / friend code (`u_…`).
  final String uid;

  /// Server-determined `human` | `bot` (analytics gate).
  final String actorType;
  final String displayName;
  final int avatar;
  final bool isGuest;
  final Set<LinkedProvider> linkedProviders;
  final int level;

  /// Total XP.
  final int xp;

  /// XP at which the current level started.
  final int levelXp;

  /// XP needed to go from this level to the next (see rest-api.md).
  final int nextLevelXp;
  final String title;
  final Loadout loadout;

  bool get isHuman => actorType == 'human';

  /// True while no non-guest provider is linked → show "Save Progress".
  bool get needsSaveProgress =>
      !linkedProviders.any((p) => p != LinkedProvider.guest);

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: _str(j['id']),
    uid: _str(j['uid']),
    actorType: _str(j['actorType'], 'human'),
    displayName: _str(j['displayName']),
    avatar: _int(j['avatar']),
    isGuest: j['isGuest'] == true,
    linkedProviders: {
      for (final p in (j['linkedProviders'] as List? ?? const []))
        if (p is String && LinkedProvider.parse(p) != null)
          LinkedProvider.parse(p)!,
    },
    level: _int(j['level'], 1),
    xp: _int(j['xp']),
    levelXp: _int(j['levelXp']),
    nextLevelXp: _int(j['nextLevelXp'], 100),
    title: _str(j['title'], 'title_rookie'),
    loadout: Loadout.fromJson(_map(j['loadout'])),
  );

  User copyWith({
    int? level,
    int? xp,
    int? levelXp,
    int? nextLevelXp,
    String? title,
    Loadout? loadout,
    Set<LinkedProvider>? linkedProviders,
    bool? isGuest,
  }) => User(
    id: id,
    uid: uid,
    actorType: actorType,
    displayName: displayName,
    avatar: avatar,
    isGuest: isGuest ?? this.isGuest,
    linkedProviders: linkedProviders ?? this.linkedProviders,
    level: level ?? this.level,
    xp: xp ?? this.xp,
    levelXp: levelXp ?? this.levelXp,
    nextLevelXp: nextLevelXp ?? this.nextLevelXp,
    title: title ?? this.title,
    loadout: loadout ?? this.loadout,
  );
}

/// `Wallet` — virtual, non-redeemable balances.
@immutable
class Wallet {
  const Wallet({required this.coins, required this.diamonds});

  final int coins;
  final int diamonds;

  static const Wallet empty = Wallet(coins: 0, diamonds: 0);

  factory Wallet.fromJson(Map<String, dynamic> j) =>
      Wallet(coins: _int(j['coins']), diamonds: _int(j['diamonds']));

  @override
  bool operator ==(Object other) =>
      other is Wallet && other.coins == coins && other.diamonds == diamonds;

  @override
  int get hashCode => Object.hash(coins, diamonds);
}

/// `AuthResponse` from every `/auth/*` endpoint.
@immutable
class AuthResponse {
  const AuthResponse({
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
    required this.isNewUser,
    required this.user,
    required this.wallet,
    this.guestSecret,
  });

  final String accessToken;
  final int accessTokenExpiresAt;
  final String refreshToken;
  final int refreshTokenExpiresAt;
  final bool isNewUser;
  final User user;
  final Wallet wallet;

  /// Only on `POST /auth/guest`.
  final String? guestSecret;

  factory AuthResponse.fromJson(Map<String, dynamic> j) => AuthResponse(
    accessToken: _str(j['accessToken']),
    accessTokenExpiresAt: _int(j['accessTokenExpiresAt']),
    refreshToken: _str(j['refreshToken']),
    refreshTokenExpiresAt: _int(j['refreshTokenExpiresAt']),
    isNewUser: j['isNewUser'] == true,
    user: User.fromJson(_map(j['user'])),
    wallet: Wallet.fromJson(_map(j['wallet'])),
    guestSecret: j['guestSecret'] is String ? j['guestSecret'] as String : null,
  );
}

/// `GET /me` and `POST /account/link/{provider}` response.
@immutable
class MeResponse {
  const MeResponse({required this.user, required this.wallet});

  final User user;
  final Wallet wallet;

  factory MeResponse.fromJson(Map<String, dynamic> j) => MeResponse(
    user: User.fromJson(_map(j['user'])),
    wallet: Wallet.fromJson(_map(j['wallet'])),
  );
}
