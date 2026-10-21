import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/protocol/models.dart' show EmoteAsset;
import '../../store/data/store_api.dart';
import '../../store/domain/store_models.dart' show EmoteFilter;
import 'quick_chat.dart';

/// An emote the user can send (`chat.emote` with [id]): a built-in emote
/// painted by the app, or a Store emote (`em_…`) drawn from its cached
/// [asset].
@immutable
class OwnedEmote {
  const OwnedEmote(this.id, {this.asset, this.name});

  final String id;

  /// The art of a Store emote; null for built-in emotes.
  final EmoteAsset? asset;

  /// Server name of a Store emote (built-ins are localized by id).
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is OwnedEmote &&
      other.id == id &&
      other.asset == asset &&
      other.name == name;

  @override
  int get hashCode => Object.hash(id, asset, name);
}

/// The starter emotes every account owns, as [OwnedEmote]s.
final List<OwnedEmote> kStarterOwnedEmotes = List.unmodifiable([
  for (final id in kStarterEmotes) OwnedEmote(id),
]);

/// Most Store emote pages the picker loads (50 per page).
const int _maxStorePages = 10;

/// Emotes the user owns, in picker order: the built-in emotes from
/// `GET /collection` (`kind == "emote"`, `owned == true`, catalog order),
/// then the Store emotes bought with diamonds (`GET /store/emotes?filter=owned`,
/// shelf order). Falls back to the starter emotes when the collection cannot
/// be loaded, and to the built-ins alone when the Store cannot (the server
/// still rejects unowned emotes with `item_not_owned`).
final ownedEmotesProvider = FutureProvider.autoDispose<List<OwnedEmote>>((
  ref,
) async {
  final api = ref.read(apiClientProvider);
  final store = ref.read(storeApiProvider);
  final (builtIn, bought) = await (
    _builtInEmotes(api),
    _storeEmotes(store),
  ).wait;
  return List.unmodifiable([...builtIn, ...bought]);
}, retry: (_, _) => null);

Future<List<OwnedEmote>> _builtInEmotes(ApiClient api) async {
  try {
    final json = await api.get('/collection');
    final items = json['items'];
    if (items is! List) return kStarterOwnedEmotes;
    final owned = <OwnedEmote>[
      for (final item in items)
        if (item is Map &&
            item['kind'] == 'emote' &&
            item['owned'] == true &&
            item['id'] is String)
          OwnedEmote(item['id'] as String),
    ];
    return owned.isEmpty ? kStarterOwnedEmotes : owned;
  } catch (e) {
    debugPrint('owned emotes unavailable: $e');
    return kStarterOwnedEmotes;
  }
}

Future<List<OwnedEmote>> _storeEmotes(StoreApi store) async {
  final out = <OwnedEmote>[];
  final seen = <String>{};
  String? cursor;
  try {
    for (var page = 0; page < _maxStorePages; page++) {
      final p = await store.listEmotes(
        filter: EmoteFilter.owned,
        cursor: cursor,
        limit: 50,
      );
      for (final e in p.items) {
        final asset = e.asset;
        if (asset == null || !seen.add(e.id)) continue;
        out.add(OwnedEmote(e.id, asset: asset, name: e.name));
      }
      cursor = p.nextCursor;
      if (cursor == null) break;
    }
  } catch (e) {
    debugPrint('store emotes unavailable: $e');
  }
  return out;
}
