import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/protocol/json_read.dart';
import '../../../core/protocol/protocol.dart';

/// `GET /rooms/code/{code}` preview (rest-api.md → Rooms).
@immutable
class RoomPreview {
  const RoomPreview({
    required this.game,
    required this.variant,
    required this.capacity,
    required this.players,
    required this.status,
    required this.entryFee,
    required this.hostName,
  });

  final String game;
  final String variant;
  final int capacity;
  final int players;

  /// `lobby` | `playing` | `finished` | `closed`.
  final String status;
  final int entryFee;
  final String hostName;

  bool get isFull => players >= capacity;
  bool get inProgress => status == RoomStatuses.playing;
  bool get isClosed =>
      status == RoomStatuses.closed || status == RoomStatuses.finished;
  bool get canJoin => status == RoomStatuses.lobby && !isFull;

  /// Error code that joining would hit (null when joinable).
  String? get blockingCode => inProgress
      ? 'room_in_progress'
      : isClosed
      ? 'room_closed'
      : isFull
      ? 'room_full'
      : null;

  factory RoomPreview.fromJson(Map<String, dynamic> j) => RoomPreview(
    game: readString(j['game'], GameIds.ludo),
    variant: readString(j['variant'], GameVariants.classic),
    capacity: readInt(j['capacity'], 4),
    players: readInt(j['players']),
    status: readString(j['status'], RoomStatuses.lobby),
    entryFee: readInt(j['entryFee']),
    hostName: readString(j['hostName']),
  );
}

/// A friend from `GET /friends` (only accepted friends are invitable).
@immutable
class FriendSummary {
  const FriendSummary({
    required this.uid,
    required this.name,
    this.avatar = 0,
    this.level = 1,
    this.online = false,
  });

  /// Public id (`u_…`) — used only as the `room.invite` target.
  final String uid;
  final String name;
  final int avatar;
  final int level;
  final bool online;

  factory FriendSummary.fromJson(Map<String, dynamic> j) => FriendSummary(
    uid: readString(j['uid']),
    name: readString(j['name']),
    avatar: readInt(j['avatar']),
    level: readInt(j['level'], 1),
    online: readBool(j['online']),
  );
}

/// REST calls used by the private-room screens. Throws `ApiException`.
abstract interface class RoomsRepository {
  Future<RoomPreview> preview(String code);

  /// Accepted friends, online first (server order).
  Future<List<FriendSummary>> friends();
}

class ApiRoomsRepository implements RoomsRepository {
  ApiRoomsRepository(this._api);

  final ApiClient _api;

  @override
  Future<RoomPreview> preview(String code) async {
    final json = await _api.get('/rooms/code/${Uri.encodeComponent(code)}');
    return RoomPreview.fromJson(json);
  }

  @override
  Future<List<FriendSummary>> friends() async {
    final json = await _api.get('/friends');
    return [
      for (final f in readList(json['friends']))
        FriendSummary.fromJson(readMap(f)),
    ];
  }
}

final roomsRepositoryProvider = Provider<RoomsRepository>(
  (ref) => ApiRoomsRepository(ref.watch(apiClientProvider)),
);
