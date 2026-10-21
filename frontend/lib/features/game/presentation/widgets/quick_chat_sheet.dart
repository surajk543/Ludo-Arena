import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/owned_emotes.dart';
import '../../application/quick_chat.dart';
import '../play_text.dart';

/// What the user picked in the quick-chat panel.
sealed class QuickChatPick {
  const QuickChatPick();
}

final class QuickMessagePick extends QuickChatPick {
  const QuickMessagePick(this.id);
  final String id;
}

final class EmotePick extends QuickChatPick {
  const EmotePick(this.emoteId);
  final String emoteId;
}

/// Compact quick-chat panel: the 8 predefined messages (localized), the
/// user's owned emotes and a local "mute other players" switch. Never free
/// text. Buttons are disabled while the client-side throttle cools down.
class QuickChatSheet extends ConsumerStatefulWidget {
  const QuickChatSheet({
    super.key,
    required this.throttle,
    required this.localMuted,
    required this.settingsMuted,
    required this.onPick,
    required this.onMuteChanged,
  });

  final QuickChatThrottle throttle;
  final bool localMuted;
  final bool settingsMuted;
  final ValueChanged<QuickChatPick> onPick;
  final ValueChanged<bool> onMuteChanged;

  static Future<void> show(
    BuildContext context, {
    required QuickChatThrottle throttle,
    required bool localMuted,
    required bool settingsMuted,
    required ValueChanged<QuickChatPick> onPick,
    required ValueChanged<bool> onMuteChanged,
  }) {
    final l10n = AppLocalizations.of(context);
    return AppBottomSheet.show<void>(
      context,
      title: l10n.playChatTitle,
      builder: (_) => QuickChatSheet(
        throttle: throttle,
        localMuted: localMuted,
        settingsMuted: settingsMuted,
        onPick: onPick,
        onMuteChanged: onMuteChanged,
      ),
    );
  }

  @override
  ConsumerState<QuickChatSheet> createState() => _QuickChatSheetState();
}

class _QuickChatSheetState extends ConsumerState<QuickChatSheet> {
  Timer? _tick;
  late bool _muted = widget.localMuted;

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  void _scheduleTick() {
    _tick?.cancel();
    final wait = widget.throttle.cooldown();
    if (wait == Duration.zero) return;
    _tick = Timer(wait + const Duration(milliseconds: 30), () {
      if (!mounted) return;
      setState(() {});
      _scheduleTick();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _pick(QuickChatPick pick) {
    if (!widget.throttle.canSend) return;
    widget.onPick(pick);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final cooldown = widget.throttle.cooldown();
    final enabled = cooldown == Duration.zero;
    final emotes = ref.watch(ownedEmotesProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!enabled)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              l10n.playChatCooldown((cooldown.inMilliseconds / 1000).ceil()),
              textAlign: TextAlign.center,
              style: context.textTheme.labelMedium?.copyWith(
                color: c.textSecondary,
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 420 ? 4 : 2;
            final width =
                (constraints.maxWidth - AppSpacing.sm * (columns - 1)) /
                columns;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final id in kQuickChatIds)
                  SizedBox(
                    width: width,
                    child: _ChatChip(
                      label: PlayText.quickChat(l10n, id) ?? id,
                      enabled: enabled,
                      onTap: () => _pick(QuickMessagePick(id)),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.playChatEmotes, style: context.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 60,
          child: emotes.when(
            data: (ids) => ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ids.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) => _EmoteButton(
                emoteId: ids[i],
                enabled: enabled,
                onTap: () => _pick(EmotePick(ids[i])),
              ),
            ),
            loading: () => const Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.xs),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _muted || widget.settingsMuted,
          onChanged: widget.settingsMuted
              ? null
              : (v) {
                  setState(() => _muted = v);
                  widget.onMuteChanged(v);
                },
          title: Text(
            l10n.playChatMuteOthers,
            style: context.textTheme.bodyLarge,
          ),
          subtitle: widget.settingsMuted
              ? Text(
                  l10n.playChatMutedBySettings,
                  style: context.textTheme.bodySmall,
                )
              : null,
        ),
      ],
    );
  }
}

class _ChatChip extends StatelessWidget {
  const _ChatChip({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: enabled
          ? c.brandSoft.withValues(alpha: c.isDark ? 0.25 : 0.8)
          : c.surfaceSunken,
      borderRadius: AppRadii.mdAll,
      child: InkWell(
        borderRadius: AppRadii.mdAll,
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.labelLarge?.copyWith(
                  color: enabled ? c.textPrimary : c.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmoteButton extends StatelessWidget {
  const _EmoteButton({
    required this.emoteId,
    required this.enabled,
    required this.onTap,
  });

  final String emoteId;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: c.surfaceSunken,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: EmoteIcon(emoteId: emoteId, size: 44),
          ),
        ),
      ),
    );
  }
}
