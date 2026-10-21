import 'package:flutter/widgets.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';

import 'seat_color.dart';

/// Localized strings for the board library.
///
/// Uses the ambient [AppLocalizations] when the app registered its delegate
/// and falls back to English otherwise, so the widgets also work in isolated
/// previews and tests.
AppLocalizations boardsL10n(BuildContext context) {
  return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      lookupAppLocalizations(const Locale('en'));
}

/// Localized seat color name ("Red", "लाल", …).
String boardsColorName(AppLocalizations l10n, SeatColor color) {
  switch (color) {
    case SeatColor.red:
      return l10n.boardsColorRed;
    case SeatColor.green:
      return l10n.boardsColorGreen;
    case SeatColor.yellow:
      return l10n.boardsColorYellow;
    case SeatColor.blue:
      return l10n.boardsColorBlue;
  }
}
