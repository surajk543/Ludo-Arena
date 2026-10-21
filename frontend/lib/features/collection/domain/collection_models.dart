import 'package:flutter/foundation.dart';

import '../../../core/network/api_models.dart';
import '../../../core/protocol/json_read.dart';

/// Equip slots (`PUT /collection/loadout`). Emotes and badges are owned,
/// not equipped.
const List<String> kEquipSlots = [
  'dice',
  'token',
  'ludo_board',
  'snakes_board',
  'frame',
  'title',
  'victory',
  'trail',
];

/// Collection Room tabs, in display order.
const List<String> kCollectionKinds = [
  'dice',
  'token',
  'ludo_board',
  'snakes_board',
  'trail',
  'victory',
  'frame',
  'title',
  'badge',
  'emote',
];

/// Fixed purchase price (exactly one currency is positive).
@immutable
class Price {
  const Price({this.coins = 0, this.diamonds = 0});

  factory Price.fromJson(Map<String, dynamic> j) =>
      Price(coins: readInt(j['coins']), diamonds: readInt(j['diamonds']));

  final int coins;
  final int diamonds;

  bool get inDiamonds => diamonds > 0;
  int get amount => inDiamonds ? diamonds : coins;

  /// Whether [wallet] covers this price (display only; the server decides).
  bool affordableWith(Wallet? wallet) {
    if (wallet == null) return true;
    return inDiamonds ? wallet.diamonds >= diamonds : wallet.coins >= coins;
  }

  /// How much is missing from [wallet].
  int shortfall(Wallet? wallet) {
    if (wallet == null) return 0;
    final have = inDiamonds ? wallet.diamonds : wallet.coins;
    return amount > have ? amount - have : 0;
  }
}

/// How an item is obtained.
enum AcquisitionType {
  starter,
  level,
  mission,
  event,
  purchase,
  unknown;

  static AcquisitionType parse(String raw) => switch (raw) {
    'starter' => starter,
    'level' => level,
    'mission' => mission,
    'event' => event,
    'purchase' => purchase,
    _ => unknown,
  };
}

@immutable
class Acquisition {
  const Acquisition({
    required this.type,
    this.level,
    this.price,
    this.label = '',
  });

  factory Acquisition.fromJson(Map<String, dynamic> j) {
    final p = readMapOrNull(j['price']);
    return Acquisition(
      type: AcquisitionType.parse(readString(j['type'])),
      level: readIntOrNull(j['level']),
      price: p == null ? null : Price.fromJson(p),
      label: readString(j['label']),
    );
  }

  final AcquisitionType type;
  final int? level;
  final Price? price;

  /// Server English fallback.
  final String label;

  bool get isPurchasable => type == AcquisitionType.purchase && price != null;
}

/// `CollectionItem`.
@immutable
class CollectionItem {
  const CollectionItem({
    required this.id,
    required this.kind,
    this.name = '',
    this.description = '',
    this.rarity = 'common',
    this.owned = false,
    this.equipped = false,
    this.acquisition = const Acquisition(type: AcquisitionType.unknown),
  });

  factory CollectionItem.fromJson(Map<String, dynamic> j) => CollectionItem(
    id: readString(j['id']),
    kind: readString(j['kind']),
    name: readString(j['name']),
    description: readString(j['description']),
    rarity: readString(j['rarity'], 'common'),
    owned: readBool(j['owned']),
    equipped: readBool(j['equipped']),
    acquisition: Acquisition.fromJson(readMap(j['acquisition'])),
  );

  final String id;
  final String kind;
  final String name;
  final String description;
  final String rarity;
  final bool owned;
  final bool equipped;
  final Acquisition acquisition;

  bool get equippable => kEquipSlots.contains(kind);
  bool get isStarter => acquisition.type == AcquisitionType.starter;

  /// Not owned and buyable for a fixed price: on sale in the Shop.
  bool get canPurchase => !owned && acquisition.isPurchasable;

  /// Sold in the Shop for a fixed price (owned or not).
  bool get inShopCatalog => acquisition.isPurchasable;

  /// Shown in the Collection Room: everything owned (starter, bought,
  /// earned) plus what can still be earned by playing (level, mission,
  /// event), shown locked. Items for sale and not owned live in the Shop.
  bool get inCollection =>
      owned || acquisition.type != AcquisitionType.purchase;

  CollectionItem copyWith({bool? owned, bool? equipped}) => CollectionItem(
    id: id,
    kind: kind,
    name: name,
    description: description,
    rarity: rarity,
    owned: owned ?? this.owned,
    equipped: equipped ?? this.equipped,
    acquisition: acquisition,
  );
}

/// Owned/locked filter of the Collection Room.
enum CollectionFilter { all, owned, locked }

/// `GET /collection`.
@immutable
class CollectionData {
  const CollectionData({required this.items, required this.loadout});

  factory CollectionData.fromJson(Map<String, dynamic> j) => CollectionData(
    items: List.unmodifiable(
      readList(j['items']).map((i) => CollectionItem.fromJson(readMap(i))),
    ),
    loadout: Loadout.fromJson(readMap(j['loadout'])),
  );

  final List<CollectionItem> items;
  final Loadout loadout;

  CollectionItem? byId(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  int get ownedCount => items.where((i) => i.owned).length;

  /// Items the Collection Room shows (owned or still to earn).
  int get collectionCount => items.where((i) => i.inCollection).length;

  int ownedOf(String kind) =>
      items.where((i) => i.kind == kind && i.owned).length;

  /// Items of [kind] the Collection Room shows (owned or still to earn).
  int totalOf(String kind) =>
      items.where((i) => i.kind == kind && i.inCollection).length;

  /// Collection Room items of [kind] matching [filter], in catalog order.
  List<CollectionItem> filtered(String kind, CollectionFilter filter) => [
    for (final i in items)
      if (i.kind == kind &&
          i.inCollection &&
          switch (filter) {
            CollectionFilter.all => true,
            CollectionFilter.owned => i.owned,
            CollectionFilter.locked => !i.owned,
          })
        i,
  ];

  /// Items of [kind] on sale in the Shop (priced, not owned yet), in
  /// catalog order.
  List<CollectionItem> shopItems(String kind) => [
    for (final i in items)
      if (i.kind == kind && i.canPurchase) i,
  ];

  /// Copy with [loadout] applied to the equipped flags.
  CollectionData withLoadout(Loadout loadout) => CollectionData(
    loadout: loadout,
    items: List.unmodifiable([
      for (final i in items)
        i.equippable ? i.copyWith(equipped: loadout.slot(i.kind) == i.id) : i,
    ]),
  );

  CollectionData replaceItem(CollectionItem item) => CollectionData(
    loadout: loadout,
    items: List.unmodifiable([
      for (final i in items) i.id == item.id ? item : i,
    ]),
  );
}
