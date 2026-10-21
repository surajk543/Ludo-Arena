import '../../../core/protocol/protocol.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Localized names and labels shared by the play screens.
abstract final class PlayText {
  static String game(AppLocalizations l10n, String game) =>
      game == GameIds.snakesLadders
      ? l10n.commonGameSnakesLadders
      : l10n.commonGameLudo;

  static String variant(AppLocalizations l10n, String variant) =>
      variant == GameVariants.quick
      ? l10n.commonVariantQuick
      : l10n.commonVariantClassic;

  /// "Ludo · Classic" (Snakes & Ladders has no variant).
  static String gameTitle(AppLocalizations l10n, String g, String v) =>
      g == GameIds.ludo
      ? l10n.playGameVariantTitle(game(l10n, g), variant(l10n, v))
      : game(l10n, g);

  /// Online / Private room / Practice.
  static String mode(AppLocalizations l10n, String mode) => switch (mode) {
    RoomModes.private => l10n.playModePrivate,
    RoomModes.practice => l10n.playModePractice,
    _ => l10n.playModeOnline,
  };

  /// Display text of a predefined quick-chat id (never free text). Unknown
  /// ids (newer server) return null and are not shown.
  static String? quickChat(AppLocalizations l10n, String id) => switch (id) {
    QuickChatIds.gg => l10n.playChatGg,
    QuickChatIds.niceMove => l10n.playChatNiceMove,
    QuickChatIds.wellPlayed => l10n.playChatWellPlayed,
    QuickChatIds.rematch => l10n.playChatRematch,
    QuickChatIds.again => l10n.playChatAgain,
    QuickChatIds.goodLuck => l10n.playChatGoodLuck,
    QuickChatIds.oops => l10n.playChatOops,
    QuickChatIds.thanks => l10n.playChatThanks,
    _ => null,
  };

  /// Player display name; empty names fall back to a neutral label. Bots
  /// are never labelled, so a legacy leading "Bot " in a bot's name is
  /// dropped.
  static String playerName(AppLocalizations l10n, RoomPlayer p) {
    final name = p.name.trim();
    if (name.isEmpty) return l10n.playSeatPlayer(p.seat + 1);
    return p.bot ? withoutBotPrefix(name) : name;
  }

  /// `Bot Bolt` → `Bolt` (unchanged when nothing would remain).
  static String withoutBotPrefix(String name) {
    final m = RegExp(r'^bot\s+', caseSensitive: false).firstMatch(name);
    if (m == null) return name;
    final rest = name.substring(m.end).trim();
    return rest.isEmpty ? name : rest;
  }
}
