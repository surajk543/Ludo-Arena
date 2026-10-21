import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../authentication/application/session_controller.dart';
import '../../meta_routes.dart';
import '../../progression/application/meta_support.dart';
import '../../progression/presentation/widgets/meta_scaffold.dart';
import '../../progression/presentation/widgets/pill_tabs.dart';
import '../application/friends_controller.dart';
import '../domain/social_models.dart';
import 'widgets/add_friend_sheet.dart';
import 'widgets/friend_code_card.dart';
import 'widgets/friend_tile.dart';

/// Tabs of the Friends screen.
enum FriendsTab {
  friends,
  requests,
  recent;

  static FriendsTab parse(String? raw) => switch (raw) {
    'requests' => requests,
    'recent' => recent,
    _ => friends,
  };
}

/// Friend code, add by code, friends (online first), incoming/outgoing
/// requests, recent opponents and a link to the weekly ranking.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key, this.initialTab});

  final String? initialTab;

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  late FriendsTab _tab = FriendsTab.parse(widget.initialTab);

  AppLocalizations get _l10n => AppLocalizations.of(context);

  Future<void> _refresh() async {
    try {
      await Future.wait([
        ref.read(friendsProvider.notifier).refresh(),
        if (_tab == FriendsTab.recent)
          ref.read(recentPlayersProvider.notifier).refresh(),
      ]);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, metaErrorMessage(_l10n, e), kind: ToastKind.error);
    }
  }

  void _toastFailure(FriendActionOutcome outcome) {
    if (outcome is FriendActionFailed && mounted) {
      AppToast.show(
        context,
        metaErrorMessage(_l10n, outcome.error),
        kind: ToastKind.error,
      );
    }
  }

  Future<void> _addFriend({String? code}) async {
    final friend = await AddFriendSheet.show(context, initialCode: code);
    if (friend == null || !mounted) return;
    AppToast.show(
      context,
      friend.status == FriendStatus.friend
          ? _l10n.metaNowFriends(friend.name)
          : _l10n.metaRequestSent(friend.name),
      kind: ToastKind.success,
    );
  }

  Future<void> _accept(Friend f) async {
    final outcome = await ref.read(friendsProvider.notifier).accept(f.uid);
    if (outcome is FriendActionSucceeded && mounted) {
      ref
          .read(recentPlayersProvider.notifier)
          .applyStatus(f.uid, FriendStatus.friend);
      AppToast.show(
        context,
        _l10n.metaNowFriends(f.name),
        kind: ToastKind.success,
      );
    }
    _toastFailure(outcome);
  }

  Future<void> _decline(Friend f) async {
    final outcome = await ref.read(friendsProvider.notifier).remove(f.uid);
    if (outcome is FriendActionSucceeded && mounted) {
      AppToast.show(context, _l10n.metaRequestDeclined);
    }
    _toastFailure(outcome);
  }

  Future<void> _cancel(Friend f) async {
    final outcome = await ref.read(friendsProvider.notifier).remove(f.uid);
    if (outcome is FriendActionSucceeded && mounted) {
      AppToast.show(context, _l10n.metaRequestCancelled);
    }
    _toastFailure(outcome);
  }

  Future<void> _remove(Friend f) async {
    final ok = await AppDialog.show<bool>(
      context,
      title: _l10n.metaRemoveFriendTitle(f.name),
      message: _l10n.metaRemoveFriendMessage,
      actions: [
        AppDialogAction(
          label: _l10n.metaRemove,
          variant: PremiumButtonVariant.danger,
          value: true,
        ),
        AppDialogAction(
          label: _l10n.commonCancel,
          variant: PremiumButtonVariant.ghost,
          value: false,
        ),
      ],
    );
    if (ok != true || !mounted) return;
    final outcome = await ref.read(friendsProvider.notifier).remove(f.uid);
    if (outcome is FriendActionSucceeded && mounted) {
      AppToast.show(context, _l10n.metaFriendRemoved(f.name));
    }
    _toastFailure(outcome);
  }

  Future<void> _requestFromRecent(Friend p) async {
    final outcome = await ref.read(friendsProvider.notifier).sendRequest(p.uid);
    if (!mounted) return;
    if (outcome case FriendActionSucceeded(:final friend?)) {
      ref
          .read(recentPlayersProvider.notifier)
          .applyStatus(p.uid, friend.status);
      AppToast.show(
        context,
        friend.status == FriendStatus.friend
            ? _l10n.metaNowFriends(p.name)
            : _l10n.metaRequestSent(p.name),
        kind: ToastKind.success,
      );
    }
    if (outcome is FriendActionFailed &&
        outcome.error.code == 'already_friends') {
      ref
          .read(recentPlayersProvider.notifier)
          .applyStatus(p.uid, FriendStatus.friend);
      return;
    }
    _toastFailure(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final user = ref.watch(sessionControllerProvider.select((s) => s.user));
    final async = ref.watch(friendsProvider);
    final lists = async.value;

    final slivers = <Widget>[
      if (user != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          sliver: SliverToBoxAdapter(
            child: FriendCodeCard(uid: user.uid, onAddFriend: _addFriend),
          ),
        ),
      SliverPadding(
        padding: kMetaPagePadding.copyWith(bottom: AppSpacing.md),
        sliver: SliverToBoxAdapter(child: _RankingTeaser()),
      ),
      SliverToBoxAdapter(
        child: MetaPillTabs<FriendsTab>(
          key: const ValueKey('friends-tabs'),
          selected: _tab,
          onSelected: (t) => setState(() => _tab = t),
          pills: [
            MetaPill(
              value: FriendsTab.friends,
              label: l10n.metaTabFriends,
              icon: Icons.people_alt_rounded,
              trailing: lists == null ? null : '${lists.friends.length}',
            ),
            MetaPill(
              value: FriendsTab.requests,
              label: l10n.metaTabRequests,
              icon: Icons.mark_email_unread_rounded,
              badge: lists?.incoming.length ?? 0,
            ),
            MetaPill(
              value: FriendsTab.recent,
              label: l10n.metaTabRecent,
              icon: Icons.history_rounded,
            ),
          ],
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
      ..._tabBody(context, async),
    ];

    return MetaScaffold(
      title: l10n.metaFriendsTitle,
      onRefresh: _refresh,
      actions: [
        IconButton(
          tooltip: l10n.metaLeaderboardTitle,
          icon: const Icon(Icons.leaderboard_rounded),
          onPressed: () => context.push(MetaRoutes.leaderboard),
        ),
      ],
      slivers: slivers,
    );
  }

  List<Widget> _tabBody(BuildContext context, AsyncValue<FriendsLists> async) {
    final l10n = _l10n;
    if (_tab == FriendsTab.recent) return _recentBody(context);
    switch (async) {
      case AsyncValue(:final value?):
        return _tab == FriendsTab.friends
            ? _friendsBody(context, value)
            : _requestsBody(context, value);
      case AsyncError(:final error):
        return [
          MetaErrorSliver(
            message: metaErrorMessage(l10n, error),
            onRetry: () => ref.invalidate(friendsProvider),
          ),
        ];
      default:
        return const [MetaLoadingSliver()];
    }
  }

  SliverPadding _list(List<Widget> children) => SliverPadding(
    padding: kMetaPagePadding,
    sliver: SliverList.separated(
      itemCount: children.length,
      itemBuilder: (_, i) => children[i],
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
    ),
  );

  List<Widget> _friendsBody(BuildContext context, FriendsLists lists) {
    final l10n = _l10n;
    if (lists.friends.isEmpty) {
      return [
        MetaEmptySliver(
          title: l10n.metaNoFriendsTitle,
          message: l10n.metaNoFriendsMessage,
          illustration: const _PeopleIllustration(),
        ),
      ];
    }
    return [
      _list([
        for (final f in lists.friends)
          FriendTile(
            key: ValueKey('friend-${f.uid}'),
            player: f,
            showOnline: true,
            trailing: PopupMenuButton<String>(
              tooltip: l10n.metaMoreActions,
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (_) => _remove(f),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_remove_rounded,
                        color: context.colors.danger,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(child: Text(l10n.metaRemoveFriend)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ]),
    ];
  }

  List<Widget> _requestsBody(BuildContext context, FriendsLists lists) {
    final l10n = _l10n;
    if (lists.incoming.isEmpty && lists.outgoing.isEmpty) {
      return [
        MetaEmptySliver(
          title: l10n.metaNoRequestsTitle,
          message: l10n.metaNoRequestsMessage,
          illustration: const _PeopleIllustration(),
        ),
      ];
    }
    return [
      if (lists.incoming.isNotEmpty) ...[
        SliverPadding(
          padding: kMetaPagePadding,
          sliver: SliverToBoxAdapter(
            child: SectionHeader(title: l10n.metaIncomingRequests),
          ),
        ),
        _list([
          for (final f in lists.incoming)
            FriendTile(
              key: ValueKey('incoming-${f.uid}'),
              player: f,
              subtitle: l10n.metaWantsToBeFriends,
              footer: Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  RowActionButton(
                    key: ValueKey('decline-${f.uid}'),
                    label: l10n.metaDecline,
                    primary: false,
                    onPressed: () => _decline(f),
                  ),
                  RowActionButton(
                    key: ValueKey('accept-${f.uid}'),
                    label: l10n.metaAccept,
                    icon: Icons.check_rounded,
                    onPressed: () => _accept(f),
                  ),
                ],
              ),
            ),
        ]),
      ],
      if (lists.outgoing.isNotEmpty) ...[
        SliverPadding(
          padding: kMetaPagePadding.copyWith(top: AppSpacing.md),
          sliver: SliverToBoxAdapter(
            child: SectionHeader(title: l10n.metaOutgoingRequests),
          ),
        ),
        _list([
          for (final f in lists.outgoing)
            FriendTile(
              key: ValueKey('outgoing-${f.uid}'),
              player: f,
              subtitle: l10n.metaRequestPending,
              trailing: RowActionButton(
                key: ValueKey('cancel-${f.uid}'),
                label: l10n.commonCancel,
                primary: false,
                onPressed: () => _cancel(f),
              ),
            ),
        ]),
      ],
    ];
  }

  List<Widget> _recentBody(BuildContext context) {
    final l10n = _l10n;
    final async = ref.watch(recentPlayersProvider);
    switch (async) {
      case AsyncValue(:final value?):
        if (value.isEmpty) {
          return [
            MetaEmptySliver(
              title: l10n.metaNoRecentTitle,
              message: l10n.metaNoRecentMessage,
              illustration: const _PeopleIllustration(),
            ),
          ];
        }
        return [
          SliverPadding(
            padding: kMetaPagePadding.copyWith(bottom: AppSpacing.sm),
            sliver: SliverToBoxAdapter(
              child: Text(
                l10n.metaRecentHint,
                style: context.textTheme.bodySmall,
              ),
            ),
          ),
          _list([
            for (final p in value)
              FriendTile(
                key: ValueKey('recent-${p.uid}'),
                player: p,
                trailing: _recentAction(p),
              ),
          ]),
        ];
      case AsyncError(:final error):
        return [
          MetaErrorSliver(
            message: metaErrorMessage(l10n, error),
            onRetry: () => ref.invalidate(recentPlayersProvider),
          ),
        ];
      default:
        return const [MetaLoadingSliver()];
    }
  }

  Widget _recentAction(Friend p) {
    final l10n = _l10n;
    final c = context.colors;
    Widget label(String text, IconData icon) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: c.textSecondary),
        const SizedBox(width: 4),
        Text(text, style: context.textTheme.labelMedium),
      ],
    );
    return switch (p.status) {
      FriendStatus.friend => label(l10n.metaFriendsLabel, Icons.people_rounded),
      FriendStatus.outgoing => label(
        l10n.metaRequested,
        Icons.schedule_rounded,
      ),
      FriendStatus.incoming => RowActionButton(
        key: ValueKey('recent-accept-${p.uid}'),
        label: l10n.metaAccept,
        icon: Icons.check_rounded,
        onPressed: () => _accept(p),
      ),
      FriendStatus.none => RowActionButton(
        key: ValueKey('recent-add-${p.uid}'),
        label: l10n.metaAdd,
        icon: Icons.person_add_alt_1_rounded,
        onPressed: () => _requestFromRecent(p),
      ),
    };
  }
}

class _RankingTeaser extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return SurfaceCard(
      onTap: () => context.push(MetaRoutes.leaderboard),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: c.goldGradient,
            ),
            child: Icon(Icons.leaderboard_rounded, color: c.onGold, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.metaLeaderboardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleMedium,
                ),
                Text(
                  l10n.metaLeaderboardTeaser,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.textMuted),
        ],
      ),
    );
  }
}

class _PeopleIllustration extends StatelessWidget {
  const _PeopleIllustration();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: SizedBox(
        width: 120,
        height: 96,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [c.brandSoft, c.brandSoft.withValues(alpha: 0)],
                ),
              ),
            ),
            const PositionedDirectional(
              start: 14,
              top: 22,
              child: PlayerAvatar(avatarIndex: 2, size: 48),
            ),
            const PositionedDirectional(
              end: 14,
              top: 22,
              child: PlayerAvatar(avatarIndex: 7, size: 48),
            ),
            Positioned(
              bottom: 6,
              child: Icon(Icons.favorite_rounded, color: c.seats.red, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}
