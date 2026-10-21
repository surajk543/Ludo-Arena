import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Connection state of the realtime WebSocket, shown by `ConnectionIndicator`.
enum RealtimeStatus {
  /// Not started (signed out / before the gate is ready).
  idle,

  /// First connection attempt in progress.
  connecting,

  /// `connection.ready` received; commands can be sent.
  connected,

  /// Connection dropped; backing off / reconnecting.
  reconnecting,

  /// Backgrounded or no network; waiting to resume.
  offline,

  /// Closed with 4409: signed in on another device. No auto-reconnect.
  replaced,
}

/// Holds the current [RealtimeStatus]. `RealtimeConnection` writes it;
/// widgets watch it.
class RealtimeStatusController extends Notifier<RealtimeStatus> {
  @override
  RealtimeStatus build() => RealtimeStatus.idle;

  void set(RealtimeStatus status) {
    if (state != status) state = status;
  }
}

final realtimeStatusProvider =
    NotifierProvider<RealtimeStatusController, RealtimeStatus>(
      RealtimeStatusController.new,
    );
