import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while the user is inside a running match screen. Game screens set it
/// on enter and clear it on exit:
///
/// ```dart
/// ref.read(inMatchProvider.notifier).set(true);   // initState / on enter
/// ref.read(inMatchProvider.notifier).set(false);  // dispose / on exit
/// ```
///
/// Non-blocking prompts (optional update, analytics consent) are deferred
/// while this is true. Blocking states (maintenance, force update) still
/// apply because the server pauses or rejects the match anyway.
class InMatchController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}

final inMatchProvider = NotifierProvider<InMatchController, bool>(
  InMatchController.new,
);
