import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the studio intro (the Sun Game Studio logo animation on the
/// splash, `StudioIntro`) is still playing. It plays once per app launch.
///
/// The startup gate (policy check, session restore, wallet) runs underneath
/// meanwhile. Until the intro ends:
/// - the router keeps the splash route (`gateRedirect`);
/// - the lobby music waits (`lobbyMusicWanted`);
/// - startup dialogs (optional update, analytics consent) wait (`AppShellHost`).
///
/// Then the app opens wherever the gate is: home when the login has finished,
/// otherwise the game splash (crest + loading) until it does.
final launchIntroPlayingProvider =
    NotifierProvider<LaunchIntroController, bool>(LaunchIntroController.new);

class LaunchIntroController extends Notifier<bool> {
  @override
  bool build() => true;

  /// Ends the intro: played to the end, or skipped (reduced motion, the
  /// animation could not be decoded, or the app left the foreground).
  /// Idempotent.
  void finish() {
    if (state) state = false;
  }
}
