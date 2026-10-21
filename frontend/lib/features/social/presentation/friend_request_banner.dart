import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/shell/tab_nav.dart';
import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/audio_haptics/haptics_service.dart';
import '../../../core/audio_haptics/reduced_motion.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/state/in_match_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'friends_screen.dart';

/// Route to the Requests tab of the Friends screen.
String friendsRequestsLocation() => Uri(
  path: AppRoutes.friends,
  queryParameters: {'tab': 'requests'},
).toString();

/// In-app banner for `social.friend_request` pushes ("Asha wants to be your
/// friend" → View). Not shown during a match; auto-dismisses after a few
/// seconds and never stacks (a newer request replaces the banner).
class FriendRequestBannerHost extends ConsumerStatefulWidget {
  const FriendRequestBannerHost({
    super.key,
    required this.child,
    this.navigatorKey,
    this.visibleFor = const Duration(seconds: 5),
  });

  final Widget child;

  /// Navigator whose overlay shows the banner; null = the nearest one.
  final GlobalKey<NavigatorState>? navigatorKey;
  final Duration visibleFor;

  @override
  ConsumerState<FriendRequestBannerHost> createState() =>
      _FriendRequestBannerHostState();
}

class _FriendRequestBannerHostState
    extends ConsumerState<FriendRequestBannerHost> {
  OverlayEntry? _entry;
  Timer? _hide;

  NavigatorState? get _navigator =>
      widget.navigatorKey?.currentState ?? Navigator.maybeOf(context);

  void _show(FriendRequestEvent e) {
    if (ref.read(inMatchProvider)) return;
    final overlay = _navigator?.overlay;
    if (overlay == null) return;
    _remove();
    ref.read(hapticsServiceProvider).light();
    ref.read(audioServiceProvider).play(Sfx.notification);
    _entry = OverlayEntry(
      builder: (ctx) => _Banner(
        name: e.fromName,
        onOpen: () {
          _remove();
          final navigator = _navigator;
          final router = navigator == null
              ? null
              : GoRouter.maybeOf(navigator.context);
          if (navigator == null || router == null) return;
          // Friends is a bottom-navigation tab (see app/shell/tab_nav.dart).
          switch (tabOpenModeFor(router.routerDelegate.currentConfiguration)) {
            case TabOpenMode.push:
              router.push(friendsRequestsLocation());
            case TabOpenMode.go:
              router.go(friendsRequestsLocation());
            case TabOpenMode.overlay:
              // Keep the play-flow page (e.g. matchmaking) underneath.
              navigator.push(
                MaterialPageRoute<void>(
                  builder: (_) => const FriendsScreen(initialTab: 'requests'),
                ),
              );
          }
        },
        onDismiss: _remove,
      ),
    );
    overlay.insert(_entry!);
    _hide = Timer(widget.visibleFor, _remove);
  }

  void _remove() {
    _hide?.cancel();
    _hide = null;
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<ServerEvent>>(socialEventsProvider, (_, next) {
      final e = next.value;
      if (e is FriendRequestEvent) _show(e);
    });
    ref.listen<bool>(inMatchProvider, (_, inMatch) {
      if (inMatch) _remove();
    });
    return widget.child;
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.name,
    required this.onOpen,
    required this.onDismiss,
  });

  final String name;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final text = l10n.metaFriendRequestBanner(name);
    Widget banner = Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: c.isDark ? BrandPalette.royal700 : BrandPalette.royal850,
          borderRadius: AppRadii.lgAll,
          border: Border.all(color: c.gold.withValues(alpha: 0.5)),
          boxShadow: c.shadow(AppElevation.high),
        ),
        child: InkWell(
          borderRadius: AppRadii.lgAll,
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: c.goldGradient,
                  ),
                  child: Icon(
                    Icons.person_add_alt_1_rounded,
                    size: 20,
                    color: c.onGold,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onOpen,
                  style: TextButton.styleFrom(
                    foregroundColor: BrandPalette.gold300,
                    minimumSize: const Size(48, 40),
                  ),
                  child: Text(l10n.metaView),
                ),
                IconButton(
                  tooltip: l10n.commonClose,
                  onPressed: onDismiss,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!context.reduceMotion) {
      banner = banner
          .animate()
          .fadeIn(duration: 200.ms)
          .slideY(begin: -0.4, curve: Curves.easeOutCubic, duration: 320.ms);
    }
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Semantics(
                liveRegion: true,
                label: text,
                child: Dismissible(
                  key: const ValueKey('friend-request-banner'),
                  direction: DismissDirection.up,
                  onDismissed: (_) => onDismiss(),
                  child: banner,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
