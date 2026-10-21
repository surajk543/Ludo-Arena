import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../game/application/play_config.dart';
import '../../game/presentation/play_nav.dart';
import '../../home/application/play_options.dart' show entryFeeProvider;
import '../../wallet/wallet_controller.dart';
import '../../game/presentation/widgets/play_form.dart';

/// `/rooms/create` — private room setup (game, Ludo variant, 2–4 seats,
/// entry fee shown). When Home already chose the configuration (query
/// parameters present) the room is created right away.
class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key, required this.request});

  final PlayRequest request;

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  late PlayRequest _config = widget.request;
  bool _creating = false;
  String? _errorCode;

  @override
  void initState() {
    super.initState();
    if (widget.request.explicit) {
      _creating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _create());
    }
  }

  Future<void> _create() async {
    if (!mounted) return;
    setState(() {
      _creating = true;
      _errorCode = null;
    });
    final controller = ref.read(activeRoomControllerProvider.notifier);
    try {
      final room = await controller.createRoom(
        game: _config.game,
        variant: _config.variant,
        capacity: _config.capacity,
      );
      if (!mounted) return;
      if (room != null) {
        PlayNav.toLobby(context, room.id);
        return;
      }
      setState(() {
        _creating = false;
        _errorCode = 'unknown';
      });
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
        _creating = false;
        _errorCode = e.code;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final locale = Localizations.localeOf(context);
    final fee = ref.watch(entryFeeProvider(_config.game));
    final wallet = ref.watch(walletControllerProvider);
    final short = wallet.isLoaded && wallet.coins < fee;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayeredBackground(
        child: SafeArea(
          child: Column(
            children: [
              PlayHeader(
                title: l10n.playCreateRoomTitle,
                onBack: () => PlayNav.exit(context),
              ),
              Expanded(
                child: _creating
                    ? LoadingState(message: l10n.playCreatingRoom)
                    : Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AppSpacing.maxContentWidth,
                          ),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.xl,
                              AppSpacing.sm,
                              AppSpacing.xl,
                              AppSpacing.xl,
                            ),
                            children: [
                              PlayGamePicker(
                                value: _config.game,
                                onChanged: (g) => setState(
                                  () => _config = _config.copyWith(game: g),
                                ),
                              ),
                              PlayFieldLabel(l10n.playPlayersLabel),
                              ChoiceChips<int>(
                                value: _config.capacity,
                                onChanged: (v) => setState(
                                  () => _config = _config.copyWith(capacity: v),
                                ),
                                options: [
                                  for (final n in const [2, 3, 4])
                                    ChoiceOption(
                                      value: n,
                                      label: l10n.commonPlayerCount(n),
                                    ),
                                ],
                              ),
                              if (_config.game == GameIds.ludo)
                                PlayVariantPicker(
                                  value: _config.variant,
                                  onChanged: (v) => setState(
                                    () =>
                                        _config = _config.copyWith(variant: v),
                                  ),
                                ),
                              const SizedBox(height: AppSpacing.lg),
                              PlayNote(
                                leading: const CoinIcon(size: 22),
                                text: l10n.playEntryFeeNote(
                                  formatCoins(fee, locale),
                                ),
                              ),
                              if (short) ...[
                                const SizedBox(height: AppSpacing.sm),
                                PlayNote(
                                  icon: Icons.warning_amber_rounded,
                                  color: c.warning,
                                  text: l10n.playNotEnoughCoinsHint(
                                    formatCoins(fee, locale),
                                  ),
                                ),
                              ],
                              if (_errorCode != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                PlayNote(
                                  icon: Icons.error_outline_rounded,
                                  color: c.danger,
                                  text: localizedErrorMessage(
                                    l10n,
                                    _errorCode!,
                                  ),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.xl),
                              PremiumButton(
                                label: l10n.playCreateRoomAction,
                                icon: Icons.meeting_room_rounded,
                                onPressed: _create,
                              ),
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
