import 'package:flutter/material.dart';

import '../../daily_journey/presentation/playtime_toast_host.dart';
import '../../social/presentation/friend_request_banner.dart';
import 'level_up_celebration_host.dart';

/// App-wide meta reactions, to be mounted ONCE above the router by the app
/// shell (core), e.g. in `app.dart`:
///
/// ```dart
/// AppShellHost(
///   child: MetaShellHost(navigatorKey: rootNavigatorKey, child: child),
/// )
/// ```
///
/// - Level-up celebrations (burst + unlocked items), deferred while
///   `inMatchProvider` is true and shown after the match screen closes.
/// - The `social.friend_request` in-app banner.
/// - Daily playtime milestone toasts (after level-ups, never in a match).
class MetaShellHost extends StatelessWidget {
  const MetaShellHost({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => LevelUpCelebrationHost(
    navigatorKey: navigatorKey,
    child: FriendRequestBannerHost(
      navigatorKey: navigatorKey,
      child: PlaytimeToastHost(navigatorKey: navigatorKey, child: child),
    ),
  );
}
