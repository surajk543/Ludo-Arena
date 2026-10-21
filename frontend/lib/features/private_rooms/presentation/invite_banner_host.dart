import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/audio_haptics/reduced_motion.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/state/in_match_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/server_clock.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../game/presentation/play_text.dart';

/// Shows a tasteful in-app banner for incoming `social.invite` events
/// ("Asha invited you to Ludo — Join / Not now"). Join opens the join
/// screen pre-filled with the invite's code (preview, then `room.join`).
///
/// Mount once above the app's navigator (e.g. wrap the router child in the
/// app shell). Invites are not shown during a match and disappear when they
/// expire (server clock).
class PlayInviteHost extends ConsumerStatefulWidget {
  const PlayInviteHost({super.key, required this.child, this.router});

  final Widget child;

  /// Router used for "Join" (defaults to the nearest `GoRouter`).
  final GoRouter? router;

  @override
  ConsumerState<PlayInviteHost> createState() => _PlayInviteHostState();
}

class _PlayInviteHostState extends ConsumerState<PlayInviteHost> {
  SocialInviteEvent? _invite;
  Timer? _expiry;

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  void _onInvite(SocialInviteEvent e) {
    if (ref.read(inMatchProvider)) return;
    final room = ref.read(activeRoomControllerProvider).room;
    if (room != null && room.id == e.roomId) return; // already there
    final clock = ref.read(serverClockProvider);
    var left = e.expiresAt > 0
        ? clock.remainingUntil(e.expiresAt)
        : const Duration(seconds: 30);
    if (left == Duration.zero) return;
    if (left > const Duration(seconds: 45)) left = const Duration(seconds: 45);
    _expiry?.cancel();
    if (_invite?.inviteId != e.inviteId) {
      ref.read(audioServiceProvider).play(Sfx.notification);
    }
    setState(() => _invite = e);
    _expiry = Timer(left, _dismiss);
  }

  void _dismiss() {
    _expiry?.cancel();
    if (mounted && _invite != null) setState(() => _invite = null);
  }

  void _join() {
    final invite = _invite;
    if (invite == null) return;
    _dismiss();
    final router = widget.router ?? GoRouter.maybeOf(context);
    router?.push(AppRoutes.joinRoomFor(code: invite.code));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<ServerEvent>>(socialEventsProvider, (_, next) {
      final e = next.value;
      if (e is SocialInviteEvent) _onInvite(e);
    });
    ref.listen<bool>(inMatchProvider, (_, inMatch) {
      if (inMatch) _dismiss();
    });
    final invite = _invite;
    final reduce = ReducedMotion.of(context);
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              duration: reduce ? Duration.zero : AppDurations.medium,
              transitionBuilder: (child, animation) => SlideTransition(
                position: Tween(
                  begin: const Offset(0, -1),
                  end: Offset.zero,
                ).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: invite == null
                  ? const SizedBox.shrink()
                  : InviteBanner(
                      key: ValueKey(invite.inviteId),
                      invite: invite,
                      onJoin: _join,
                      onDismiss: _dismiss,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The banner itself (exposed for previews / tests).
class InviteBanner extends StatelessWidget {
  const InviteBanner({
    super.key,
    required this.invite,
    required this.onJoin,
    required this.onDismiss,
  });

  final SocialInviteEvent invite;
  final VoidCallback onJoin;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    if (l10n == null) return const SizedBox.shrink();
    final c = context.colors;
    final name = invite.fromName.trim().isEmpty
        ? l10n.playInviteSomeone
        : invite.fromName.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Material(
        color: Colors.transparent,
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 10),
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              borderRadius: AppRadii.lgAll,
              border: Border.all(color: c.gold.withValues(alpha: 0.7)),
              boxShadow: c.shadow(AppElevation.high),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: c.brandGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mail_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.playInviteIncoming(
                      name,
                      PlayText.game(l10n, invite.game),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.labelLarge,
                  ),
                ),
                TextButton(
                  onPressed: onDismiss,
                  child: Text(l10n.playInviteDismiss),
                ),
                PremiumButton(
                  label: l10n.playInviteJoin,
                  size: PremiumButtonSize.small,
                  expand: false,
                  onPressed: onJoin,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
