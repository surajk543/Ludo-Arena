import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/telemetry/telemetry_reporter.dart';

void main() {
  test('aggregates and posts once per window', () {
    fakeAsync((async) {
      final bodies = <Map<String, dynamic>>[];
      final r = TelemetryReporter(post: (b) async => bodies.add(b));
      r.record(TelemetryKind.reconnectSuccess);
      r.record(TelemetryKind.reconnectSuccess);
      r.record(TelemetryKind.hashMismatch);
      async.elapse(const Duration(seconds: 29));
      expect(bodies, isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(bodies, hasLength(1));
      final events = (bodies.single['events'] as List).cast<Map>();
      expect(
        events,
        containsAll([
          {'kind': 'reconnect_success', 'count': 2},
          {'kind': 'hash_mismatch', 'count': 1},
        ]),
      );
      // Only kind + count — no identifiers.
      for (final e in events) {
        expect(e.keys.toSet(), {'kind', 'count'});
      }
      expect(r.pending, isEmpty);
    });
  });

  test('failures never throw and keep counts for the next flush', () {
    fakeAsync((async) {
      var fail = true;
      final bodies = <Map<String, dynamic>>[];
      final r = TelemetryReporter(
        post: (b) async {
          if (fail) throw Exception('offline');
          bodies.add(b);
        },
      );
      r.record(TelemetryKind.reconnectFailure, 3);
      async.elapse(const Duration(seconds: 30));
      expect(r.pending[TelemetryKind.reconnectFailure], 3);
      fail = false;
      r.record(TelemetryKind.clientError);
      async.elapse(const Duration(seconds: 30));
      expect(bodies, hasLength(1));
      expect(r.pending, isEmpty);
    });
  });

  test('counts are capped and dispose stops posting', () {
    fakeAsync((async) {
      final bodies = <Map<String, dynamic>>[];
      final r = TelemetryReporter(
        post: (b) async => bodies.add(b),
        maxPerKind: 5,
      );
      r.record(TelemetryKind.clientError, 50);
      expect(r.pending[TelemetryKind.clientError], 5);
      r.dispose();
      r.record(TelemetryKind.clientError);
      async.elapse(const Duration(minutes: 1));
      expect(bodies, isEmpty);
    });
  });
}
