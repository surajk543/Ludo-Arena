import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/network/api_models.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/features/leaderboard/domain/leaderboard_models.dart';
import 'package:ludo_royale/features/private_rooms/application/rooms_repository.dart';
import 'package:ludo_royale/features/social/domain/report_models.dart';
import 'package:ludo_royale/features/social/domain/social_models.dart';

import '../../helpers/fake_backend.dart';
import 'fixtures.dart';

const _bear = {
  'id': 'pp_bear',
  'format': 'image',
  'path': 'profile_pictures/image/bear.png',
};
const _dots = {
  'id': 'pp_bouncing_dots',
  'format': 'lottie',
  'path': 'profile_pictures/lottie_animation/bouncing-dots.json',
};

void main() {
  group('PlayerPicture.tryParse', () {
    test('accepts image and lottie pictures', () {
      final bear = PlayerPicture.tryParse(_bear)!;
      expect(bear.id, 'pp_bear');
      expect(bear.isLottie, isFalse);
      expect(bear.toJson(), _bear);
      expect(PlayerPicture.tryParse(_dots)!.isLottie, isTrue);
    });

    test('null, missing or malformed → built-in avatar', () {
      expect(PlayerPicture.tryParse(null), isNull);
      expect(PlayerPicture.tryParse('pp_bear'), isNull);
      for (final bad in [
        {..._bear, 'id': ''},
        {..._bear, 'format': 'gif'},
        {..._bear, 'path': 'profile_pictures/../etc/passwd'},
        {..._bear, 'path': '/profile_pictures/image/bear.png'},
        {..._bear, 'path': 'avatars/bear.png'},
        {..._bear, 'path': 'profile_pictures/image/a b.png'},
        {..._bear, 'path': 'profile_pictures//bear.png'},
        {..._bear, 'path': 'profile_pictures/${'x' * 300}.png'},
      ]) {
        expect(PlayerPicture.tryParse(bad), isNull, reason: '$bad');
      }
    });
  });

  group('room players', () {
    Map<String, dynamic> withPicture(Map<String, dynamic> room) => {
      ...room,
      'players': [
        {
          ...(room['players'] as List)[0] as Map<String, dynamic>,
          'picture': _dots,
        },
        {
          ...(room['players'] as List)[1] as Map<String, dynamic>,
          'picture': null,
        },
      ],
    };

    test('seat players carry their picture (or null)', () {
      final room = RoomSnapshot.fromJson(withPicture(ludoRoomJson()));
      expect(room.players[0].picture, PlayerPicture.tryParse(_dots));
      expect(room.players[1].picture, isNull);
      expect(room.players[0].toJson()['picture'], _dots);
      // Old snapshots (no field) round-trip unchanged.
      expect(ludoRoom().players[0].toJson().containsKey('picture'), isFalse);
      expect(RoomPlayer.fromJson(room.players[0].toJson()), room.players[0]);
    });

    test('the picture never enters the state hash', () {
      final plain = ludoRoom();
      final dressed = RoomSnapshot.fromJson(withPicture(ludoRoomJson()));
      expect(StateHash.canonical(dressed), StateHash.canonical(plain));
      expect(StateHash.of(dressed), StateHash.of(plain));
    });

    test('deltas keep the picture (copyWith)', () {
      final room = RoomSnapshot.fromJson(withPicture(ludoRoomJson()));
      final r = RoomStateReducer().reduce(
        room,
        PlayerConnectionEvent(
          roomId: room.id,
          v: room.v + 1,
          h: StateHash.of(room),
          seat: 0,
          connected: false,
        ),
      );
      final next = (r as Applied).state;
      expect(next.players[0].connected, isFalse);
      expect(next.players[0].picture, room.players[0].picture);
    });
  });

  group('REST models', () {
    test('User.picture parses and copyWith can clear or keep it', () {
      final user = User.fromJson({...userJson(), 'picture': _bear});
      expect(user.picture!.path, 'profile_pictures/image/bear.png');
      expect(user.copyWith(level: 9).picture, user.picture);
      expect(user.copyWith(picture: null).picture, isNull);
      expect(User.fromJson(userJson()).picture, isNull);
    });

    test('friends, recent players, leaderboard rows, reports and invite '
        'lists parse the picture', () {
      final friend = Friend.fromJson({
        'uid': 'u_1',
        'name': 'Ravi',
        'picture': _dots,
      });
      expect(friend.picture!.isLottie, isTrue);
      expect(friend.copyWith(online: true).picture, friend.picture);
      expect(
        LeaderboardEntry.fromJson({
          'uid': 'u_1',
          'name': 'Ravi',
          'rank': 1,
          'picture': _bear,
        }).picture,
        isNotNull,
      );
      expect(
        ReportedPlayer.fromJson({
          'uid': 'u_1',
          'name': 'R',
          'picture': _bear,
        }).picture,
        isNotNull,
      );
      expect(
        FriendSummary.fromJson({
          'uid': 'u_1',
          'name': 'R',
          'picture': _bear,
        }).picture,
        isNotNull,
      );
      expect(Friend.fromJson({'uid': 'u_2', 'name': 'N'}).picture, isNull);
    });
  });
}
