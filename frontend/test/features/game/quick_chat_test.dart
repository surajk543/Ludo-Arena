import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/features/game/application/quick_chat.dart';

void main() {
  group('QuickChatThrottle (1 per 3 s, 10 per minute)', () {
    late DateTime now;
    late QuickChatThrottle t;

    setUp(() {
      now = DateTime(2026, 10, 21, 12);
      t = QuickChatThrottle(now: () => now);
    });

    test('allows one message per 3 seconds', () {
      expect(t.tryAcquire(), isTrue);
      expect(t.canSend, isFalse);
      expect(t.cooldown(), const Duration(seconds: 3));
      now = now.add(const Duration(seconds: 2));
      expect(t.tryAcquire(), isFalse);
      expect(t.cooldown(), const Duration(seconds: 1));
      now = now.add(const Duration(seconds: 1));
      expect(t.tryAcquire(), isTrue);
    });

    test('caps at 10 messages per sliding minute', () {
      for (var i = 0; i < 10; i++) {
        expect(t.tryAcquire(), isTrue, reason: 'message $i');
        now = now.add(const Duration(seconds: 3));
      }
      // 30 s after the first message: the minute budget is spent.
      expect(t.tryAcquire(), isFalse);
      expect(t.cooldown(), const Duration(seconds: 30));
      now = now.add(const Duration(seconds: 30));
      expect(t.tryAcquire(), isTrue);
    });

    test('reset clears the history', () {
      t.tryAcquire();
      t.reset();
      expect(t.canSend, isTrue);
    });
  });

  group('ChatMutePolicy', () {
    test('own messages are always shown', () {
      const p = ChatMutePolicy(settingsMuted: true, localMuted: true);
      expect(p.shouldShow(fromSelf: true), isTrue);
    });

    test('settings mute or local mute hide other players', () {
      expect(
        const ChatMutePolicy(
          settingsMuted: true,
          localMuted: false,
        ).shouldShow(fromSelf: false),
        isFalse,
      );
      expect(
        const ChatMutePolicy(
          settingsMuted: false,
          localMuted: true,
        ).shouldShow(fromSelf: false),
        isFalse,
      );
      expect(
        const ChatMutePolicy(
          settingsMuted: false,
          localMuted: false,
        ).shouldShow(fromSelf: false),
        isTrue,
      );
    });
  });

  test('exactly the 8 predefined quick-chat ids are offered', () {
    expect(kQuickChatIds, QuickChatIds.all);
    expect(kQuickChatIds, hasLength(8));
  });
}
