import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../application/rooms_repository.dart';

/// Lists the user's friends (`GET /friends`) and sends `room.invite` to an
/// online friend. Offline friends are shown but cannot be invited (the
/// server only delivers invites to online friends).
class InviteFriendsSheet extends ConsumerStatefulWidget {
  const InviteFriendsSheet({super.key});

  static Future<void> show(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppBottomSheet.show<void>(
      context,
      title: l10n.playInviteSheetTitle,
      builder: (_) => const InviteFriendsSheet(),
    );
  }

  @override
  ConsumerState<InviteFriendsSheet> createState() => _InviteFriendsSheetState();
}

class _InviteFriendsSheetState extends ConsumerState<InviteFriendsSheet> {
  late Future<List<FriendSummary>> _friends = _load();
  final Set<String> _sent = {};
  final Set<String> _sending = {};

  Future<List<FriendSummary>> _load() =>
      ref.read(roomsRepositoryProvider).friends();

  Future<void> _invite(FriendSummary f) async {
    if (_sent.contains(f.uid) || _sending.contains(f.uid)) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _sending.add(f.uid));
    try {
      await ref.read(activeRoomControllerProvider.notifier).invite(f.uid);
      if (mounted) setState(() => _sent.add(f.uid));
    } on RealtimeCommandException catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          localizedErrorMessage(l10n, e.code),
          kind: ToastKind.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _sending.remove(f.uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    return FutureBuilder<List<FriendSummary>>(
      future: _friends,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          final err = snap.error;
          return ErrorState(
            title: l10n.playInviteError,
            message: err is ApiException
                ? localizedErrorMessage(l10n, err.code)
                : null,
            onRetry: () => setState(() => _friends = _load()),
          );
        }
        final friends = snap.data ?? const [];
        if (friends.isEmpty) {
          return EmptyState(
            title: l10n.playInviteEmptyTitle,
            message: l10n.playInviteEmptyMessage,
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in friends)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    PlayerAvatar(
                      avatarIndex: f.avatar,
                      size: 44,
                      dimmed: !f.online,
                      semanticLabel: f.name,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.titleSmall,
                          ),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: f.online ? c.success : c.textMuted,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  f.online
                                      ? l10n.playFriendOnline
                                      : l10n.playFriendOffline,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    PremiumButton(
                      label: _sent.contains(f.uid)
                          ? l10n.playInviteSent
                          : l10n.playInviteSend,
                      icon: _sent.contains(f.uid)
                          ? Icons.check_rounded
                          : Icons.send_rounded,
                      size: PremiumButtonSize.small,
                      expand: false,
                      loading: _sending.contains(f.uid),
                      variant: _sent.contains(f.uid)
                          ? PremiumButtonVariant.ghost
                          : PremiumButtonVariant.primary,
                      onPressed: f.online && !_sent.contains(f.uid)
                          ? () => _invite(f)
                          : null,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
