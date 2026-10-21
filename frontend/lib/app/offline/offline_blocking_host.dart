import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio_haptics/reduced_motion.dart';
import '../../core/realtime/realtime_providers.dart';
import '../../core/state/in_match_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'offline_block_controller.dart';

/// Blocks the whole app while the connection is lost
/// ([offlineBlockProvider]): a full-screen scrim with a "Connection lost"
/// card over every route, dialog and bottom sheet.
///
/// Mounted once in `MaterialApp.builder`, above the router, so it covers the
/// root navigator (pushed routes, dialogs, sheets) and the app-wide banners.
/// While blocked it:
/// - absorbs taps and gestures (including the iOS edge swipe-back),
/// - removes focus below it (closes the keyboard) and hides that UI from
///   screen readers,
/// - swallows system back through a priority child of the router's
///   [BackButtonDispatcher], and reports to Android that the app handles
///   back (predictive back would otherwise close the app from a tab root).
///
/// Nothing is sent while blocked; when the socket is back the room
/// controller re-syncs (`connection.ready` → `game.request_sync`) and the
/// overlay clears.
class OfflineBlockingHost extends ConsumerStatefulWidget {
  const OfflineBlockingHost({
    super.key,
    required this.child,
    this.backButtonDispatcher,
  });

  final Widget child;

  /// The router's root dispatcher (`GoRouter.backButtonDispatcher`).
  final BackButtonDispatcher? backButtonDispatcher;

  @override
  ConsumerState<OfflineBlockingHost> createState() =>
      _OfflineBlockingHostState();
}

class _OfflineBlockingHostState extends ConsumerState<OfflineBlockingHost> {
  /// How long the "Back online" live region stays in the tree where
  /// announcements are not supported (Android).
  static const Duration _backOnlineNoteFor = Duration(seconds: 3);

  bool _blocked = false;
  ChildBackButtonDispatcher? _backBlocker;
  Timer? _backOnlineNote;

  /// What the routes below last reported (restored when unblocked).
  bool _routesHandleBack = true;

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(
      offlineBlockProvider,
      (_, blocked) => _onBlockedChanged(blocked),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _releaseBack();
    _backOnlineNote?.cancel();
    super.dispose();
  }

  void _onBlockedChanged(bool blocked) {
    if (blocked == _blocked) return;
    _blocked = blocked;
    if (blocked) {
      _takeBack();
      _backOnlineNote?.cancel();
      _backOnlineNote = null;
    } else {
      _releaseBack();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _blocked != blocked) return;
      NavigationNotification(
        canHandlePop: blocked || _routesHandleBack,
      ).dispatch(context);
      if (!blocked &&
          ref.read(realtimeStatusProvider) == RealtimeStatus.connected) {
        _announceBackOnline();
      }
    });
  }

  void _takeBack() {
    final parent = widget.backButtonDispatcher;
    if (parent == null || _backBlocker != null) return;
    _backBlocker = parent.createChildBackButtonDispatcher()
      ..addCallback(_swallowBack)
      ..takePriority();
  }

  void _releaseBack() {
    _backBlocker?.removeCallback(_swallowBack);
    _backBlocker = null;
  }

  Future<bool> _swallowBack() => SynchronousFuture(true);

  /// iOS (and other platforms that support it): an announcement. Android
  /// deprecated those, so a short-lived live region is shown instead.
  void _announceBackOnline() {
    if (MediaQuery.supportsAnnounceOf(context)) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        AppLocalizations.of(context).connectionBackOnline,
        Directionality.of(context),
      );
      return;
    }
    _backOnlineNote?.cancel();
    setState(() {
      _backOnlineNote = Timer(_backOnlineNoteFor, () {
        if (mounted) setState(() => _backOnlineNote = null);
      });
    });
  }

  bool _onRouteNavigation(NavigationNotification n) {
    _routesHandleBack = n.canHandlePop;
    // While blocked the app keeps claiming back (see _onBlockedChanged).
    return _blocked;
  }

  @override
  Widget build(BuildContext context) {
    final blocked = ref.watch(offlineBlockProvider);
    return NotificationListener<NavigationNotification>(
      onNotification: _onRouteNavigation,
      child: Stack(
        children: [
          ExcludeSemantics(
            excluding: blocked,
            child: ExcludeFocus(
              excluding: blocked,
              child: AbsorbPointer(absorbing: blocked, child: widget.child),
            ),
          ),
          if (blocked)
            const Positioned.fill(child: OfflineBlockingOverlay())
          else if (_backOnlineNote != null)
            PositionedDirectional(
              top: 0,
              start: 0,
              child: Semantics(
                container: true,
                liveRegion: true,
                label: AppLocalizations.of(context).connectionBackOnline,
                child: const SizedBox.square(dimension: 1),
              ),
            ),
        ],
      ),
    );
  }
}

/// The scrim + "Connection lost" card (exposed for tests and previews).
class OfflineBlockingOverlay extends ConsumerWidget {
  const OfflineBlockingOverlay({super.key});

  /// The "Try now" button stays busy this long after a tap.
  static const Duration retryCooldown = Duration(seconds: 2);

  static const double _maxCardWidth = 380;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final text = context.textTheme;
    final l10n = AppLocalizations.of(context);
    final inMatch = ref.watch(inMatchProvider);

    final card = SurfaceCard(
      elevation: AppElevation.high,
      borderRadius: AppRadii.xlAll,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // One live region: announced once when the overlay appears.
          Semantics(
            container: true,
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ExcludeSemantics(child: _OfflineIndicator()),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.connectionLostTitle,
                  textAlign: TextAlign.center,
                  style: text.titleLarge?.copyWith(color: c.textPrimary),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.connectionLostMessage,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: c.textSecondary),
                ),
                if (inMatch) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.connectionLostMatchHint,
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: c.textMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          PremiumButton(
            label: l10n.connectionLostRetryNow,
            icon: Icons.refresh_rounded,
            variant: PremiumButtonVariant.secondary,
            size: PremiumButtonSize.medium,
            onPressed: () {
              ref.read(offlineBlockProvider.notifier).retryNow();
              return Future<void>.delayed(retryCooldown);
            },
          ),
        ],
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: ModalBarrier(
              dismissible: false,
              color: Colors.black.withValues(alpha: c.isDark ? 0.65 : 0.5),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.gutter),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxCardWidth),
                    child: Semantics(
                      scopesRoute: true,
                      explicitChildNodes: true,
                      child: card,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Spinning ring around a "no signal" glyph; static with reduced motion.
class _OfflineIndicator extends StatelessWidget {
  const _OfflineIndicator();

  static const double _size = 64;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduce = context.reduceMotion;
    return Container(
      key: const ValueKey('offline-indicator'),
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.surfaceSunken,
        border: reduce
            ? Border.all(color: c.warning.withValues(alpha: 0.7), width: 3)
            : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!reduce)
            Positioned.fill(
              child: CircularProgressIndicator(
                strokeWidth: 3.2,
                strokeCap: StrokeCap.round,
                valueColor: AlwaysStoppedAnimation(c.warning),
                backgroundColor: c.goldSoft,
              ),
            ),
          Icon(Icons.wifi_off_rounded, size: 28, color: c.warning),
        ],
      ),
    );
  }
}
