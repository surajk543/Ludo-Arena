import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics_providers.dart';
import '../../../core/lifecycle/app_lifecycle.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../authentication/application/session_controller.dart';
import '../../meta_routes.dart';
import '../../progression/application/meta_support.dart';
import '../../progression/presentation/widgets/meta_scaffold.dart';
import '../../progression/presentation/widgets/pill_tabs.dart';
import '../application/friends_controller.dart';
import '../application/reports_controller.dart';
import '../domain/social_models.dart';
import 'widgets/add_friend_sheet.dart';
import 'widgets/friend_code_card.dart';
import 'widgets/friend_tile.dart';
import 'widgets/reports_list.dart';

/// Tabs of the Friends screen (`/friends?tab=…`).
enum FriendsTab {
  friends,
  requests,
  recent,
  reported;

  static FriendsTab parse(String? raw) => switch (raw) {
    'requests' => requests,
    'recent' => recent,
    'reported' => reported,
    _ => friends,
  };
}

/// Friend code, add by code, friends (online now / offline), incoming and
/// outgoing requests, recent opponents, my player reports and a link to the
/// weekly ranking. While visible (and the app is in the foreground) the
/// friends list refreshes every [autoRefreshInterval] and on app resume.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key, this.initialTab});

  final String? initialTab;

  static const Duration autoRefreshInterval = Duration(seconds: 30);

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  late FriendsTab _tab = FriendsTab.parse(widget.initialTab);
  Timer? _autoRefresh;
  StreamSubscription<void>? _resumed;

  /// Not covered by another (opaque) route.
  bool _visible = true;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    _autoRefresh = Timer.periodic(
      FriendsScreen.autoRefreshInterval,
      (_) => _refreshPresence(),
    );
    _resumed = ref
        .read(appLifecycleProvider)
        .resumed
        .listen((_) => _refreshPresence());
  }

  @override
  void didUpdateWidget(covariant FriendsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _tab = FriendsTab.parse(widget.initialTab);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Routes pushed on top disable the tickers below them: back on screen,
    // refresh right away.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPresence());
    }
    _visible = visible;
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    _resumed?.cancel();
    super.dispose();
  }

  /// Quiet background refresh of friends and presence (errors ignored).
  void _refreshPresence() {
    if (!mounted || !_visible) return;
    if (!ref.read(appLifecycleProvider).isForeground) return;
    unawaited(
      ref.read(friendsProvider.notifier).refresh().catchError((Object _) {}),
    );
  }

  int? get _maxFriends => ref.read(friendsProvider).value?.maxFriends;

  Future<void> _refresh() async {
    try {
      await Future.wait([
        ref.read(friendsProvider.notifier).refresh(),
        if (_tab == FriendsTab.recent)
          ref.read(recentPlayersProvider.notifier).refresh(),
        if (_tab == FriendsTab.reported)
          ref.read(reportsProvider.notifier).refresh(),
      ]);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        metaErrorMessage(_l10n, e, maxFriends: _maxFriends),
        kind: ToastKind.error,
      );
    }
  }

  void _toastFailure(FriendActionOutcome outcome) {
    if (outcome is FriendActionFailed && mounted) {
      AppToast.show(
        context,
        metaErrorMessage(_l10n, outcome.error, maxFriends: _maxFriends),
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
      ref.read(analyticsServiceProvider).friendRequestSent('recent');
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
              trailing: lists == null
                  ? null
                  : '${lists.friendCount}/${lists.maxFriends}',
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
            MetaPill(
              value: FriendsTab.reported,
              label: l10n.socialTabReported,
              icon: Icons.flag_rounded,
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
    if (_tab == FriendsTab.reported) return reportedTabSlivers(context, ref);
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
    final online = [
      for (final f in lists.friends)
        if (f.online) f,
    ];
    final offline = [
      for (final f in lists.friends)
        if (!f.online) f,
    ];
    Widget header(Widget child, {double top = 0}) => SliverPadding(
      padding: kMetaPagePadding.copyWith(top: top, bottom: AppSpacing.sm),
      sliver: SliverToBoxAdapter(child: child),
    );
    return [
      header(_FriendCountHeader(lists: lists)),
      header(
        _PresenceHeader(
          key: const ValueKey('online-now-header'),
          online: true,
          text: l10n.socialOnlineNow(lists.onlineCount),
        ),
      ),
      if (online.isNotEmpty) _list([for (final f in online) _friendTile(f)]),
      if (offline.isNotEmpty) ...[
        header(
          _PresenceHeader(
            key: const ValueKey('offline-header'),
            online: false,
            text: l10n.socialOfflineCount(offline.length),
          ),
          top: AppSpacing.md,
        ),
        _list([for (final f in offline) _friendTile(f)]),
      ],
    ];
  }

  Widget _friendTile(Friend f) {
    final l10n = _l10n;
    return FriendTile(
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
    );
  }

  /// "You can have up to 20 friends — remove one to add more."
  Widget _limitNote(FriendsLists lists) => SliverPadding(
    padding: kMetaPagePadding.copyWith(bottom: AppSpacing.sm),
    sliver: SliverToBoxAdapter(
      child: MetaNote(
        key: const ValueKey('friend-limit-note'),
        text: _l10n.socialFriendLimitNote(lists.maxFriends),
        icon: Icons.group_rounded,
      ),
    ),
  );

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
    final full = lists.atFriendLimit;
    return [
      if (lists.incoming.isNotEmpty) ...[
        if (full) _limitNote(lists),
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
                    onPressed: full ? null : () => _accept(f),
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
    final lists = ref.watch(friendsProvider).value;
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
          if (lists != null && lists.atFriendLimit) _limitNote(lists),
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
    final full = ref.watch(friendsProvider).value?.atFriendLimit ?? false;
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
        onPressed: full ? null : () => _accept(p),
      ),
      FriendStatus.none => RowActionButton(
        key: ValueKey('recent-add-${p.uid}'),
        label: l10n.metaAdd,
        icon: Icons.person_add_alt_1_rounded,
        onPressed: full ? null : () => _requestFromRecent(p),
      ),
    };
  }
}

/// "Friends 12/20" with a slim fill bar; the limit note when full.
class _FriendCountHeader extends StatelessWidget {
  const _FriendCountHeader({required this.lists});

  final FriendsLists lists;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final full = lists.atFriendLimit;
    final fraction = lists.maxFriends <= 0
        ? 0.0
        : (lists.friendCount / lists.maxFriends).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.people_alt_rounded,
              size: 18,
              color: full ? c.warning : c.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xs + 2),
            Expanded(
              child: Text(
                l10n.socialFriendsCount(lists.friendCount, lists.maxFriends),
                key: const ValueKey('friend-count'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: AppRadii.pillAll,
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 4,
              color: full ? c.warning : c.brand,
              backgroundColor: c.surfaceSunken,
            ),
          ),
        ),
        if (full) ...[
          const SizedBox(height: AppSpacing.sm),
          MetaNote(
            key: const ValueKey('friend-limit-note'),
            text: l10n.socialFriendLimitNote(lists.maxFriends),
            icon: Icons.group_rounded,
          ),
        ],
      ],
    );
  }
}

/// "Online now (3)" with a green presence dot / "Offline (5)".
class _PresenceHeader extends StatelessWidget {
  const _PresenceHeader({super.key, required this.online, required this.text});

  final bool online;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      header: true,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? c.success : c.textMuted,
              boxShadow: online
                  ? [
                      BoxShadow(
                        color: c.success.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.titleMedium?.copyWith(
                color: online ? c.textPrimary : c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
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
