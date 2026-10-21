import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../collection/domain/collection_models.dart';

/// Shop category of the coin packs (real-money purchases). Always first, and
/// where the Shop opens.
const String kCoinsCategory = 'coins';

/// Shop / Collection category of the profile pictures (the other categories
/// are cosmetic kinds such as `dice`).
const String kPictureCategory = 'picture';

/// Cosmetic kinds sold in the Shop while the catalogue is loading: the kinds
/// of `backend/config/catalog.json` with priced items, in Collection order.
/// Once `GET /collection` answers, the categories come from its data.
const List<String> kDefaultShopKinds = [
  'dice',
  'token',
  'ludo_board',
  'snakes_board',
  'trail',
  'victory',
  'frame',
  'emote',
];

/// Shop / Collection category of emotes: the catalogue's priced emotes
/// plus the Store's animated emotes (`GET /store/emotes`).
const String kShopEmoteCategory = 'emote';

/// The Shop's categories: Coins, Pictures, then every cosmetic kind with
/// priced items (owned or not; a kind whose items are all owned shows an
/// "all yours" state rather than disappearing), in Collection order. Emotes
/// are always sold (the Store's animated emotes).
List<String> shopCategories(CollectionData? data) => [
  kCoinsCategory,
  kPictureCategory,
  if (data == null)
    ...kDefaultShopKinds
  else
    for (final k in kCollectionKinds)
      if (k == kShopEmoteCategory ||
          data.items.any((i) => i.kind == k && i.inShopCatalog))
        k,
];

/// The Shop category on screen (not persisted). Opening the Shop always
/// starts on [kCoinsCategory] unless a `?category=` deep link names another.
class ShopCategoryController extends Notifier<String> {
  @override
  String build() => kCoinsCategory;

  void select(String category) => state = category;
}

final shopCategoryProvider = NotifierProvider<ShopCategoryController, String>(
  ShopCategoryController.new,
);
