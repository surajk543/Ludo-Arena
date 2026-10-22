import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/protocol/protocol.dart';
import 'package:ludo_arena/core/realtime/realtime_connection.dart';
import 'package:ludo_arena/core/realtime/realtime_status.dart';

import 'fakes.dart';

/// websocket-protocol.md §1: 4401 with reason `account deleted` (after
/// `DELETE /account`) is final — no refresh, no reconnect, and it is not the
/// "signed in on another device" case.
void main() {
  FakeSocket connect(Harness h, FakeAsync async) {
    h.connection.start();
    async.flushMicrotasks();
    final s = h.connector.last;
    s.ready(serverTime: 1761022800000);
    async.flushMicrotasks();
    return s;
  }

  test('4401 + "account deleted" → halt, no refresh, callback fired', () {
    fakeAsync((async) {
      final h = Harness();
      final s = connect(h, async);
      s.serverClose(WsCloseCodes.sessionRevoked, WsCloseReasons.accountDeleted);
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 5));
      expect(h.refreshCalls, 0);
      expect(h.accountDeletedCalls, 1);
      expect(h.connector.calls, hasLength(1));
      expect(h.connection.haltReason, RealtimeHaltReason.accountDeleted);
      expect(h.status, RealtimeStatus.idle);
      expect(h.statuses, isNot(contains(RealtimeStatus.replaced)));
    });
  });

  test('4401 with another reason still refreshes and reconnects', () {
    fakeAsync((async) {
      final h = Harness();
      final s = connect(h, async);
      s.serverClose(WsCloseCodes.sessionRevoked, 'session revoked');
      async.flushMicrotasks();
      expect(h.refreshCalls, 1);
      expect(h.accountDeletedCalls, 0);
      expect(h.connector.calls, hasLength(2));
    });
  });

  test('start() after an account-deleted halt clears the halt', () {
    fakeAsync((async) {
      final h = Harness();
      final s = connect(h, async);
      s.serverClose(WsCloseCodes.sessionRevoked, WsCloseReasons.accountDeleted);
      async.flushMicrotasks();
      h.connection.stop();
      h.connection.start();
      async.flushMicrotasks();
      expect(h.connection.haltReason, isNull);
      expect(h.connector.calls, hasLength(2));
    });
  });
}
