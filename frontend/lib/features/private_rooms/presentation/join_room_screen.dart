import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../game/presentation/play_nav.dart';
import '../../game/presentation/play_text.dart';
import '../../game/presentation/widgets/play_form.dart';
import '../application/room_code.dart';
import '../application/rooms_repository.dart';

/// `/rooms/join?code=` — 6-character code input (A-Z / 2-9 without I, O,
/// 0, 1; case-insensitive, auto upper-case, always LTR), a REST preview of
/// the room before joining, and the join over WebSocket.
class JoinRoomScreen extends ConsumerStatefulWidget {
  const JoinRoomScreen({super.key, this.initialCode});

  final String? initialCode;

  @override
  ConsumerState<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends ConsumerState<JoinRoomScreen> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  int _lookup = 0;

  bool _invalidPrefill = false;
  bool _loadingPreview = false;
  RoomPreview? _preview;
  String? _previewError;
  String? _joinError;
  bool _joining = false;

  String get _code => _controller.text;
  bool get _complete => RoomCode.isValid(_code);

  @override
  void initState() {
    super.initState();
    final raw = widget.initialCode ?? '';
    _invalidPrefill = raw.isNotEmpty && RoomCode.hasInvalidCharacters(raw);
    _controller = TextEditingController(text: RoomCode.sanitize(raw));
    if (_complete && !_invalidPrefill) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchPreview());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    setState(() {
      _invalidPrefill = false;
      _preview = null;
      _previewError = null;
      _joinError = null;
      _loadingPreview = false;
    });
    _lookup++;
    if (_complete) {
      _debounce = Timer(const Duration(milliseconds: 250), _fetchPreview);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || !mounted) return;
    final code = RoomCode.sanitize(text);
    _controller.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
    _onChanged(code);
  }

  Future<void> _fetchPreview() async {
    if (!mounted || !_complete) return;
    final code = _code;
    final ticket = ++_lookup;
    setState(() {
      _loadingPreview = true;
      _previewError = null;
    });
    try {
      final preview = await ref.read(roomsRepositoryProvider).preview(code);
      if (!mounted || ticket != _lookup) return;
      setState(() {
        _preview = preview;
        _loadingPreview = false;
      });
    } on ApiException catch (e) {
      if (!mounted || ticket != _lookup) return;
      setState(() {
        _loadingPreview = false;
        _previewError = e.status == 404 || e.code == 'not_found'
            ? 'invalid_code'
            : e.code;
      });
    } catch (_) {
      if (!mounted || ticket != _lookup) return;
      setState(() {
        _loadingPreview = false;
        _previewError = 'unknown';
      });
    }
  }

  Future<void> _join() async {
    if (!_complete || _joining) return;
    setState(() {
      _joining = true;
      _joinError = null;
    });
    final controller = ref.read(activeRoomControllerProvider.notifier);
    try {
      final room = await controller.joinRoom(_code);
      if (!mounted) return;
      final live = room ?? ref.read(activeRoomControllerProvider).room;
      if (live != null) {
        PlayNav.toRoom(context, live);
      } else {
        setState(() {
          _joining = false;
          _joinError = 'unknown';
        });
      }
    } on RealtimeCommandException catch (e) {
      if (!mounted) return;
      final live = ref.read(activeRoomControllerProvider).room;
      if (e.code == 'already_in_room' &&
          live != null &&
          (live.isLobby || live.isPlaying)) {
        PlayNav.toRoom(context, live);
        return;
      }
      setState(() {
        _joining = false;
        _joinError = e.code;
      });
    }
  }

  String? _hint(AppLocalizations l10n) {
    if (_invalidPrefill) return l10n.playJoinInvalidChars;
    final missing = RoomCode.length - _code.length;
    if (missing > 0 && _code.isNotEmpty) {
      return l10n.playJoinCodeIncomplete(missing);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final hint = _hint(l10n);
    final blocking = _preview?.blockingCode;
    final error = _joinError ?? _previewError ?? blocking;
    final canJoin =
        _complete && !_invalidPrefill && _preview != null && blocking == null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayeredBackground(
        child: SafeArea(
          child: Column(
            children: [
              PlayHeader(
                title: l10n.playJoinTitle,
                onBack: () => PlayNav.exit(context),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.maxContentWidth,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.md,
                        AppSpacing.xl,
                        AppSpacing.xl,
                      ),
                      children: [
                        Text(
                          l10n.playJoinHint,
                          textAlign: TextAlign.center,
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        // Room codes are Latin identifiers: always LTR.
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: TextField(
                            key: const Key('room-code-field'),
                            controller: _controller,
                            focusNode: _focus,
                            autofocus: widget.initialCode == null,
                            textAlign: TextAlign.center,
                            textCapitalization: TextCapitalization.characters,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.visiblePassword,
                            textInputAction: TextInputAction.go,
                            maxLength: RoomCode.length,
                            inputFormatters: const [RoomCodeInputFormatter()],
                            style: context.textTheme.headlineMedium?.copyWith(
                              letterSpacing: 8,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                            decoration: InputDecoration(
                              hintText: '••••••',
                              counterText: '',
                              prefixIcon: Icon(
                                Icons.vpn_key_rounded,
                                color: c.brand,
                              ),
                              suffixIcon: IconButton(
                                tooltip: l10n.playPaste,
                                onPressed: _paste,
                                icon: const Icon(Icons.content_paste_rounded),
                              ),
                            ),
                            onChanged: _onChanged,
                            onSubmitted: (_) => canJoin ? _join() : null,
                          ),
                        ),
                        if (hint != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            hint,
                            textAlign: TextAlign.center,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: _invalidPrefill
                                  ? c.danger
                                  : c.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        if (_loadingPreview)
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Flexible(child: Text(l10n.playJoinLookingUp)),
                              ],
                            ),
                          )
                        else if (_preview != null)
                          RoomPreviewCard(preview: _preview!),
                        if (error != null && !_loadingPreview) ...[
                          const SizedBox(height: AppSpacing.md),
                          PlayNote(
                            icon: Icons.error_outline_rounded,
                            color: c.danger,
                            text: localizedErrorMessage(l10n, error),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        PremiumButton(
                          label: _joining
                              ? l10n.playJoining
                              : l10n.playJoinAction,
                          icon: Icons.login_rounded,
                          loading: _joining,
                          sound: Sfx.lobbyPlay,
                          onPressed: canJoin ? _join : null,
                        ),
                        if (_previewError != null &&
                            _previewError != 'invalid_code' &&
                            _complete) ...[
                          const SizedBox(height: AppSpacing.sm),
                          PremiumButton(
                            label: l10n.playTryAgain,
                            icon: Icons.refresh_rounded,
                            variant: PremiumButtonVariant.ghost,
                            size: PremiumButtonSize.medium,
                            onPressed: _fetchPreview,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Preview of a private room before joining (`GET /rooms/code/{code}`).
class RoomPreviewCard extends StatelessWidget {
  const RoomPreviewCard({super.key, required this.preview});

  final RoomPreview preview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final locale = Localizations.localeOf(context);
    final p = preview;
    final (String status, Color color) = p.inProgress
        ? (l10n.playJoinStatusInProgress, c.warning)
        : p.isClosed
        ? (l10n.playJoinStatusClosed, c.danger)
        : p.isFull
        ? (l10n.playJoinStatusFull, c.warning)
        : (l10n.playJoinStatusOpen, c.success);
    return SurfaceCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: c.brandGradient,
              borderRadius: AppRadii.mdAll,
            ),
            child: Icon(
              p.game == GameIds.snakesLadders
                  ? Icons.stairs_rounded
                  : Icons.grid_view_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PlayText.gameTitle(l10n, p.game, p.variant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleMedium,
                ),
                if (p.hostName.isNotEmpty)
                  Text(
                    l10n.playJoinPreviewHost(p.hostName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall,
                  ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l10n.playJoinPreviewPlayers(p.players, p.capacity),
                      style: context.textTheme.labelMedium,
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CoinIcon(size: 14),
                        const SizedBox(width: 3),
                        Text(
                          formatCoins(p.entryFee, locale),
                          style: context.textTheme.labelMedium,
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: AppRadii.pillAll,
                      ),
                      child: Text(
                        status,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
