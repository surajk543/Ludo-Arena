import 'package:flutter/foundation.dart';

import '../../../core/protocol/json_read.dart';

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

/// `Friend` — public profile only (uid, name, avatar, level, title).
@immutable
class Friend {
  const Friend({
    required this.uid,
    required this.name,
    this.avatar = 0,
    this.level = 1,
    this.title = 'title_rookie',
    this.online = false,
    this.status = FriendStatus.none,
  });

  factory Friend.fromJson(Map<String, dynamic> j) => Friend(
    uid: readString(j['uid']),
    name: readString(j['name']),
    avatar: readInt(j['avatar']),
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
  final int level;
  final String title;

  /// Only reported for accepted friends.
  final bool online;
  final FriendStatus status;

  Friend copyWith({FriendStatus? status, bool? online}) => Friend(
    uid: uid,
    name: name,
    avatar: avatar,
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
  });

  factory FriendsLists.fromJson(Map<String, dynamic> j) => FriendsLists(
    friends: Friend.listFrom(j['friends']),
    incoming: Friend.listFrom(j['incoming']),
    outgoing: Friend.listFrom(j['outgoing']),
  );

  final List<Friend> friends;
  final List<Friend> incoming;
  final List<Friend> outgoing;

  int get onlineCount => friends.where((f) => f.online).length;

  FriendsLists _without(String uid) => FriendsLists(
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
        return FriendsLists(
          friends: List.unmodifiable(list),
          incoming: base.incoming,
          outgoing: base.outgoing,
        );
      case FriendStatus.incoming:
        return FriendsLists(
          friends: base.friends,
          incoming: List.unmodifiable([f, ...base.incoming]),
          outgoing: base.outgoing,
        );
      case FriendStatus.outgoing:
        return FriendsLists(
          friends: base.friends,
          incoming: base.incoming,
          outgoing: List.unmodifiable([f, ...base.outgoing]),
        );
      case FriendStatus.none:
        return base;
    }
  }
}
