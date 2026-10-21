import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../data/progression_api.dart';
import '../domain/progression_models.dart';
import 'meta_support.dart';

/// The level road (`GET /progression`). XP pushes update the numbers in
/// place; a level change re-fetches (milestone `reached` flags change).
class ProgressionController extends AsyncNotifier<ProgressionView> {
  @override
  Future<ProgressionView> build() {
    ref.listen<AsyncValue<ProgressionUpdatedEvent>>(
      progressionUpdatesProvider,
      (_, next) {
        final e = next.value;
        if (e != null) _onPush(e);
      },
    );
    return ref.read(progressionApiProvider).fetch();
  }

  void _onPush(ProgressionUpdatedEvent e) {
    final current = state.value;
    if (current == null) return;
    if (e.level != current.level) {
      unawaited(refresh().catchError((Object _) {}));
    } else if (e.xp != current.xp) {
      state = AsyncData(current.copyWith(xp: e.xp));
    }
  }

  /// Pull-to-refresh. Keeps the previous data on failure and rethrows the
  /// [ApiException] for a toast.
  Future<void> refresh() async {
    try {
      final v = await ref.read(progressionApiProvider).fetch();
      if (ref.mounted) state = AsyncData(v);
    } catch (e, s) {
      if (ref.mounted && !state.hasValue) state = AsyncError(e, s);
      rethrow;
    }
  }
}

final progressionViewProvider =
    AsyncNotifierProvider<ProgressionController, ProgressionView>(
      ProgressionController.new,
      isAutoDispose: true,
      retry: noRetry,
    );
