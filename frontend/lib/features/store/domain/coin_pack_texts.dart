import 'dart:ui';

import 'package:intl/intl.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../iap/iap_store.dart';
import 'coin_pack_models.dart';

/// Localized texts of a coin pack.
abstract final class CoinPackTexts {
  /// The pack's label in the app language; the server's English label for a
  /// pack this app version does not know.
  static String label(AppLocalizations l10n, CoinPack pack) =>
      switch (pack.id) {
        'coins_starter' => l10n.coinsPackStarter,
        'coins_popular' => l10n.coinsPackPopular,
        'coins_great_value' => l10n.coinsPackGreatValue,
        'coins_best_value' => l10n.coinsPackBestValue,
        _ => pack.label,
      };

  /// The store's localized price when the store knows the product, else
  /// the fallback price ([fallbackPrice]).
  static String price(Locale locale, CoinPack pack, ProductDetails? product) {
    final store = product?.price.trim();
    if (store != null && store.isNotEmpty) return store;
    return fallbackPrice(locale, pack.fallbackPrice);
  }

  /// `₹199`: whole units, the currency's symbol, the locale's digits.
  static String fallbackPrice(Locale locale, CoinPackPrice price) {
    final tag = switch (locale.languageCode) {
      'en' => 'en_IN',
      final code =>
        Intl.verifiedLocale(
              code,
              NumberFormat.localeExists,
              onFailure: (_) => 'en',
            ) ??
            'en',
    };
    return NumberFormat.simpleCurrency(
      locale: tag,
      name: price.currency,
      decimalDigits: 0,
    ).format(price.amount);
  }
}
