import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';
import 'number_format.dart';

/// Carries the user's [NumberSystem] (Settings → Number format) into the
/// app's [Localizations].
///
/// Callers format amounts from `Localizations.localeOf(context)`, so a
/// changed number system must rebuild exactly the widgets that read the
/// locale. Listing this delegate in `MaterialApp.localizationsDelegates`
/// (see [appLocalizationsDelegates]) does that without touching any caller:
/// when [system] changes, [shouldReload] makes `Localizations` reload, which
/// applies the choice to [AppNumberFormat.preferredSystem] and notifies every
/// widget that depends on the locale or `AppLocalizations` (balance chips,
/// entry fees, prices, rewards, results…) in the same frame.
class NumberSystemDelegate extends LocalizationsDelegate<NumberSystemChoice> {
  const NumberSystemDelegate(this.system);

  /// The user's choice; null follows the language.
  final NumberSystem? system;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<NumberSystemChoice> load(Locale locale) {
    AppNumberFormat.preferredSystem = system;
    return SynchronousFuture(NumberSystemChoice(system));
  }

  @override
  bool shouldReload(NumberSystemDelegate old) => old.system != system;
}

/// The resource loaded by [NumberSystemDelegate].
@immutable
class NumberSystemChoice {
  const NumberSystemChoice(this.preferred);

  /// The user's choice; null follows the language.
  final NumberSystem? preferred;
}

/// The app's `MaterialApp.localizationsDelegates`: generated strings,
/// Material/Cupertino/Widgets localizations and the number system.
List<LocalizationsDelegate<Object?>> appLocalizationsDelegates(
  NumberSystem? numberSystem,
) => [
  ...AppLocalizations.localizationsDelegates,
  NumberSystemDelegate(numberSystem),
];
