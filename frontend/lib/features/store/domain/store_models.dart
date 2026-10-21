import 'package:flutter/foundation.dart';

import '../../../core/network/api_models.dart';
import '../../../core/protocol/json_read.dart';

/// Default page size of the Store shelf (server default; 1..50).
const int kStorePageSize = 24;

/// Picture shelf filter (`GET /store/profile-pictures?filter=`). The Shop
/// offers [all], [animated] and [still] (pictures not owned yet); the
/// Collection and the Profile picker list [owned].
enum StoreFilter {
  all('all'),

  /// Lottie animations.
  animated('animated'),

  /// Still images.
  still('static'),
  owned('owned');

  const StoreFilter(this.wire);

  /// Query value.
  final String wire;
}

/// `ProfilePicture`: a Shop picture with the caller's ownership.
@immutable
class ProfilePicture {
  const ProfilePicture({
    required this.id,
    required this.name,
    required this.format,
    required this.path,
    required this.priceDiamonds,
    this.owned = false,
    this.equipped = false,
  });

  factory ProfilePicture.fromJson(Map<String, dynamic> j) => ProfilePicture(
    id: readString(j['id']),
    name: readString(j['name']),
    format: readString(j['format'], PlayerPicture.formatImage),
    path: readString(j['path']),
    priceDiamonds: readInt(readMap(j['price'])['diamonds']),
    owned: readBool(j['owned']),
    equipped: readBool(j['equipped']),
  );

  /// `pp_…`.
  final String id;

  /// Catalogue name (server data, shown as is like a proper name).
  final String name;

  /// `image` | `lottie`.
  final String format;
  final String path;

  /// Fixed price; pictures are sold for diamonds only.
  final int priceDiamonds;

  /// Bought: the player keeps it forever.
  final bool owned;

  /// The player's applied picture.
  final bool equipped;

  bool get isAnimated => format == PlayerPicture.formatLottie;

  /// Drawable form; null when the server sent an unusable path or format
  /// (the tile then shows a placeholder).
  PlayerPicture? get picture =>
      PlayerPicture.tryParse({'id': id, 'format': format, 'path': path});

  /// Whether [wallet] covers the price (display only; the server decides).
  bool affordableWith(Wallet? wallet) =>
      wallet == null || wallet.diamonds >= priceDiamonds;

  /// Diamonds missing from [wallet].
  int shortfall(Wallet? wallet) {
    if (wallet == null) return 0;
    final missing = priceDiamonds - wallet.diamonds;
    return missing > 0 ? missing : 0;
  }

  ProfilePicture copyWith({bool? owned, bool? equipped}) => ProfilePicture(
    id: id,
    name: name,
    format: format,
    path: path,
    priceDiamonds: priceDiamonds,
    owned: owned ?? this.owned,
    equipped: equipped ?? this.equipped,
  );
}

/// One page of `GET /store/profile-pictures`.
@immutable
class StorePage {
  const StorePage({
    this.items = const [],
    this.nextCursor,
    this.total = 0,
    this.equipped,
  });

  factory StorePage.fromJson(Map<String, dynamic> j) => StorePage(
    items: List.unmodifiable(
      readList(j['items'])
          .map((e) => ProfilePicture.fromJson(readMap(e)))
          .where((p) => p.id != ''),
    ),
    nextCursor: readStringOrNull(j['nextCursor']),
    total: readInt(j['total']),
    equipped: readStringOrNull(j['equipped']),
  );

  final List<ProfilePicture> items;

  /// Opaque; null on the last page.
  final String? nextCursor;

  /// Items matching the filter (all pages).
  final int total;

  /// Id of the applied picture, or null (built-in avatar).
  final String? equipped;
}
