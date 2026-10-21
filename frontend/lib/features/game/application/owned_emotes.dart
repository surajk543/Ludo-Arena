import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'quick_chat.dart';

/// Emote ids the user owns, from `GET /collection` (`kind == "emote"`,
/// `owned == true`), in catalog order. Falls back to the starter emotes when
/// the collection cannot be loaded (the server still rejects unowned emotes
/// with `item_not_owned`).
final ownedEmotesProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  try {
    final json = await ref.read(apiClientProvider).get('/collection');
    final items = json['items'];
    if (items is! List) return kStarterEmotes;
    final owned = <String>[
      for (final item in items)
        if (item is Map &&
            item['kind'] == 'emote' &&
            item['owned'] == true &&
            item['id'] is String)
          item['id'] as String,
    ];
    return owned.isEmpty ? kStarterEmotes : owned;
  } catch (e) {
    debugPrint('owned emotes unavailable: $e');
    return kStarterEmotes;
  }
}, retry: (_, _) => null);
