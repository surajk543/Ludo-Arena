import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';

const _angry = {'path': 'emotes/angry.json', 'format': 'lottie'};

EmoteEvent _decode(Map<String, dynamic> p) =>
    decodeServerMessage(jsonEncode({'t': 'chat.emote', 'p': p})).event
        as EmoteEvent;

void main() {
  group('EmoteAsset.tryParse', () {
    test('accepts lottie and image art under emotes/', () {
      final a = EmoteAsset.tryParse(_angry)!;
      expect(a.isLottie, isTrue);
      expect(a.hasSafePath, isTrue);
      expect(a.toJson(), _angry);
      expect(
        EmoteAsset.tryParse({'path': 'emotes/x.png', 'format': 'image'}),
        const EmoteAsset(format: 'image', path: 'emotes/x.png'),
      );
    });

    test('null, missing or malformed → no asset', () {
      expect(EmoteAsset.tryParse(null), isNull);
      expect(EmoteAsset.tryParse('emotes/angry.json'), isNull);
      for (final bad in [
        {..._angry, 'format': 'gif'},
        {'path': 'emotes/angry.json'},
        {'format': 'lottie'},
        {..._angry, 'path': 'emotes/../profile_pictures/x.json'},
        {..._angry, 'path': '/emotes/angry.json'},
        {..._angry, 'path': 'profile_pictures/lottie_animation/x.json'},
        {..._angry, 'path': 'emotes/a b.json'},
        {..._angry, 'path': 'emotes//angry.json'},
        {..._angry, 'path': 'emotes/${'x' * 300}.json'},
      ]) {
        expect(EmoteAsset.tryParse(bad), isNull, reason: '$bad');
      }
    });

    test('picture paths are not emote paths and vice versa', () {
      expect(EmoteAsset.isSafePath('emotes/angry.json'), isTrue);
      expect(PlayerPicture.isSafePath('emotes/angry.json'), isFalse);
      expect(EmoteAsset.isSafePath('profile_pictures/image/bear.png'), isFalse);
    });
  });

  group('chat.emote', () {
    test('a Store emote carries its asset', () {
      final e = _decode({
        'roomId': 'r_1',
        'seat': 2,
        'emote': 'em_angry',
        'asset': _angry,
      });
      expect(e.emote, 'em_angry');
      expect(e.seat, 2);
      expect(e.asset, EmoteAsset.tryParse(_angry));
    });

    test('built-in (no asset, null) and malformed assets decode without '
        'one', () {
      for (final asset in [
        null,
        {'path': '../x.json', 'format': 'lottie'},
        'emotes/angry.json',
        42,
      ]) {
        final e = _decode({
          'roomId': 'r_1',
          'seat': 1,
          'emote': 'em_angry',
          'asset': asset,
        });
        expect(e.emote, 'em_angry');
        expect(e.asset, isNull, reason: '$asset');
      }
      final builtIn = _decode({
        'roomId': 'r_1',
        'seat': 1,
        'emote': 'emote_wave',
      });
      expect(builtIn.asset, isNull);
    });
  });
}
