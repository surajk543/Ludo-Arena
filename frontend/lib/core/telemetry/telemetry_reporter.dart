import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';

/// Aggregate-only telemetry kinds accepted by `POST /telemetry/events`.
enum TelemetryKind {
  clientError('client_error'),
  hashMismatch('hash_mismatch'),
  reconnectSuccess('reconnect_success'),
  reconnectFailure('reconnect_failure');

  const TelemetryKind(this.wire);
  final String wire;
}

/// Sends `{"events":[{"kind","count"}]}` bodies.
typedef TelemetryPoster = Future<void> Function(Map<String, dynamic> body);

/// Batches privacy-conscious counters (no identifiers, no free text) and
/// posts them at most every [flushAfter]. Never throws.
class TelemetryReporter {
  TelemetryReporter({
    required this._post,
    this.flushAfter = const Duration(seconds: 30),
    this.maxPerKind = 1000,
  });

  final TelemetryPoster _post;
  final Duration flushAfter;

  /// Counts are capped so an offline device does not grow unbounded.
  final int maxPerKind;

  final Map<TelemetryKind, int> _counts = {};
  Timer? _timer;
  bool _flushing = false;
  bool _disposed = false;

  /// Pending (unsent) counts — for tests/diagnostics.
  Map<TelemetryKind, int> get pending => Map.unmodifiable(_counts);

  void record(TelemetryKind kind, [int count = 1]) {
    if (_disposed || count <= 0) return;
    _counts[kind] = ((_counts[kind] ?? 0) + count).clamp(0, maxPerKind);
    _timer ??= Timer(flushAfter, () {
      _timer = null;
      unawaited(flush());
    });
  }

  /// Sends everything pending now. Failed batches are kept for the next
  /// flush (still capped).
  Future<void> flush() async {
    if (_flushing || _counts.isEmpty) return;
    _flushing = true;
    final batch = Map<TelemetryKind, int>.of(_counts);
    _counts.clear();
    try {
      await _post({
        'events': [
          for (final e in batch.entries) {'kind': e.key.wire, 'count': e.value},
        ],
      });
    } catch (e) {
      debugPrint('telemetry: flush failed ($e)');
      for (final entry in batch.entries) {
        _counts[entry.key] = ((_counts[entry.key] ?? 0) + entry.value).clamp(
          0,
          maxPerKind,
        );
      }
    } finally {
      _flushing = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

final telemetryReporterProvider = Provider<TelemetryReporter>((ref) {
  final reporter = TelemetryReporter(
    post: (body) async {
      await ref.read(apiClientProvider).post('/telemetry/events', body: body);
    },
  );
  ref.onDispose(reporter.dispose);
  return reporter;
});
