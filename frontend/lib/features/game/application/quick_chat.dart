import 'dart:collection';

import '../../../core/protocol/protocol.dart';
import '../../../core/time/server_clock.dart';

/// Client-side mirror of the server's chat limits (websocket-protocol.md §5:
/// `chat.quick` / `chat.emote` — 1 per 3 s, 10 per minute). Quick chat and
/// emotes share one budget, which is never looser than the server's.
class QuickChatThrottle {
  QuickChatThrottle({
    NowFn? now,
    this.minInterval = const Duration(seconds: 3),
    this.maxPerWindow = 10,
    this.window = const Duration(minutes: 1),
  }) : _now = now ?? DateTime.now;

  final NowFn _now;
  final Duration minInterval;
  final int maxPerWindow;
  final Duration window;
  final Queue<DateTime> _sent = Queue<DateTime>();

  void _prune(DateTime now) {
    while (_sent.isNotEmpty && now.difference(_sent.first) >= window) {
      _sent.removeFirst();
    }
  }

  /// How long until the next message may be sent (zero = now).
  Duration cooldown() {
    final now = _now();
    _prune(now);
    var wait = Duration.zero;
    if (_sent.isNotEmpty) {
      final sinceLast = now.difference(_sent.last);
      if (sinceLast < minInterval) wait = minInterval - sinceLast;
    }
    if (_sent.length >= maxPerWindow) {
      final windowWait = window - now.difference(_sent.first);
      if (windowWait > wait) wait = windowWait;
    }
    return wait.isNegative ? Duration.zero : wait;
  }

  bool get canSend => cooldown() == Duration.zero;

  /// Records a send when allowed. Returns false (and records nothing) while
  /// cooling down.
  bool tryAcquire() {
    if (!canSend) return false;
    _sent.add(_now());
    return true;
  }

  /// Forgets the history (new match). A server `rate_limited` rejection
  /// does NOT call this: the used slot stays recorded so the client keeps
  /// backing off.
  void reset() => _sent.clear();
}

/// Who may appear in chat bubbles.
///
/// The persistent Settings → "mute quick chat" is applied by the core
/// controller (it never emits other players' messages while muted). The
/// in-match local mute hides other players' bubbles for this match only.
/// The user's own messages are always shown.
class ChatMutePolicy {
  const ChatMutePolicy({required this.settingsMuted, required this.localMuted});

  final bool settingsMuted;
  final bool localMuted;

  bool get othersMuted => settingsMuted || localMuted;

  bool shouldShow({required bool fromSelf}) => fromSelf || !othersMuted;
}

/// The eight predefined quick-chat ids in display order (never free text).
const List<String> kQuickChatIds = QuickChatIds.all;

/// Starter emotes every account owns (docs/cosmetics-catalog.md).
const List<String> kStarterEmotes = ['emote_wave', 'emote_thumbs'];
