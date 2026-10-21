import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/in_match_provider.dart';

/// Marks the subtree as "inside a match" ([inMatchProvider]) while mounted,
/// so non-blocking prompts (optional update, consent) wait until the user
/// leaves the match screen.
///
/// Uses a reference count so a route transition between two match screens
/// never flickers the flag off.
class InMatchScope extends ConsumerStatefulWidget {
  const InMatchScope({super.key, required this.child});

  final Widget child;

  @visibleForTesting
  static int get activeCount => _InMatchScopeState._active;

  @override
  ConsumerState<InMatchScope> createState() => _InMatchScopeState();
}

class _InMatchScopeState extends ConsumerState<InMatchScope> {
  static int _active = 0;
  late final InMatchController _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(inMatchProvider.notifier);
    _active++;
    _sync(_notifier);
  }

  static void _sync(InMatchController notifier) {
    // Providers must not change while the tree builds: apply after it.
    scheduleMicrotask(() {
      try {
        notifier.set(_active > 0);
      } catch (_) {
        // The container was disposed (app shutdown / test teardown).
      }
    });
  }

  @override
  void dispose() {
    _active--;
    _sync(_notifier);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
