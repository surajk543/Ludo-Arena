import 'package:flutter/foundation.dart';

import '../../../core/protocol/json_read.dart';
import '../../../core/protocol/models.dart' show PlayerPicture;

/// Relationship of another player to me.
enum FriendStatus {
  friend,
  incoming,
  outgoing,
  none;

  static FriendStatus parse(String raw) => switch (raw) {
    'friend' => friend,
    'incoming' => incoming,
    'outgoing' => outgoing,
    _ => none,
  };
}

/// `Friend` — public profile only (uid, name, avatar, picture, level, title).
@immutable
class Friend {
  const Friend({
    required this.uid,
    required this.name,
    this.avatar = 0,
    this.picture,
    this.level = 1,
    this.title = 'title_rookie',
    this.online = false,
    this.status = FriendStatus.none,
  });

  factory Friend.fromJson(Map<String, dynamic> j) => Friend(
    uid: readString(j['uid']),
    name: readString(j['name']),
    avatar: readInt(j['avatar']),
    picture: PlayerPicture.tryParse(j['picture']),
    level: readInt(j['level'], 1),
    title: readString(j['title'], 'title_rookie'),
    online: readBool(j['online']),
    status: FriendStatus.parse(readString(j['status'])),
  );

  static List<Friend> listFrom(Object? raw) =>
      List.unmodifiable(readList(raw).map((e) => Friend.fromJson(readMap(e))));

  /// Public uid / friend code. Never sent to analytics.
  final String uid;
  final String name;
  final int avatar;

  /// Store profile picture (null: the built-in [avatar]).
  final PlayerPicture? picture;
  final int level;
  final String title;

  /// Only reported for accepted friends.
  final bool online;
  final FriendStatus status;

  Friend copyWith({FriendStatus? status, bool? online}) => Friend(
    uid: uid,
    name: name,
    avatar: avatar,
    picture: picture,
    level: level,
    title: title,
    online: online ?? this.online,
    status: status ?? this.status,
  );
}

/// `GET /friends`.
@immutable
class FriendsLists {
  const FriendsLists({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
    this.maxFriends = defaultMaxFriends,
    this._serverOnlineCount,
    this._serverFriendCount,
  });

  factory FriendsLists.fromJson(Map<String, dynamic> j) {
    final max = readInt(j['maxFriends'], defaultMaxFriends);
    return FriendsLists(
      friends: Friend.listFrom(j['friends']),
      incoming: Friend.listFrom(j['incoming']),
      outgoing: Friend.listFrom(j['outgoing']),
      maxFriends: max > 0 ? max : defaultMaxFriends,
      serverOnlineCount: readIntOrNull(j['onlineCount']),
      serverFriendCount: readIntOrNull(j['friendCount']),
    );
  }

  /// Accepted-friends cap when the server does not send `maxFriends`.
  static const int defaultMaxFriends = 20;

  final List<Friend> friends;
  final List<Friend> incoming;
  final List<Friend> outgoing;

  /// Most accepted friends one player can have (server `maxFriends`).
  final int maxFriends;

  /// Server counts from the last `GET /friends`; local changes fall back
  /// to counting the lists.
  final int? _serverOnlineCount;
  final int? _serverFriendCount;

  /// Friends online right now (server `onlineCount`).
  int get onlineCount =>
      _serverOnlineCount ?? friends.where((f) => f.online).length;

  /// Accepted friends (server `friendCount`).
  int get friendCount => _serverFriendCount ?? friends.length;

  /// No more friends can be added (or requests accepted).
  bool get atFriendLimit => friendCount >= maxFriends;

  /// My relationship with [uid] according to these lists.
  FriendStatus statusOf(String uid) {
    if (friends.any((f) => f.uid == uid)) return FriendStatus.friend;
    if (incoming.any((f) => f.uid == uid)) return FriendStatus.incoming;
    if (outgoing.any((f) => f.uid == uid)) return FriendStatus.outgoing;
    return FriendStatus.none;
  }

  FriendsLists _with({
    required List<Friend> friends,
    required List<Friend> incoming,
    required List<Friend> outgoing,
  }) => FriendsLists(
    friends: friends,
    incoming: incoming,
    outgoing: outgoing,
    maxFriends: maxFriends,
  );

  FriendsLists _without(String uid) => _with(
    friends: List.unmodifiable(friends.where((f) => f.uid != uid)),
    incoming: List.unmodifiable(incoming.where((f) => f.uid != uid)),
    outgoing: List.unmodifiable(outgoing.where((f) => f.uid != uid)),
  );

  /// Removes [uid] from every list (remove / decline / cancel).
  FriendsLists remove(String uid) => _without(uid);

  /// Puts [f] into the list matching its status.
  FriendsLists upsert(Friend f) {
    final base = _without(f.uid);
    switch (f.status) {
      case FriendStatus.friend:
        final list = [...base.friends, f]
          ..sort((a, b) {
            if (a.online != b.online) return a.online ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
        return _with(
          friends: List.unmodifiable(list),
          incoming: base.incoming,
          outgoing: base.outgoing,
        );
      case FriendStatus.incoming:
        return _with(
          friends: base.friends,
          incoming: List.unmodifiable([f, ...base.incoming]),
          outgoing: base.outgoing,
        );
      case FriendStatus.outgoing:
        return _with(
          friends: base.friends,
          incoming: base.incoming,
          outgoing: List.unmodifiable([f, ...base.outgoing]),
        );
      case FriendStatus.none:
        return base;
    }
  }
}
