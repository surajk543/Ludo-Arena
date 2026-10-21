import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/preferences_store.dart';

/// Players this device muted from their match pod: their quick chat and
/// emotes are no longer shown in any match. Separate from Settings → "Mute
/// quick chat" (everyone) and from the in-match mute in the chat sheet.
///
/// Client-side only: the muted player is not told and the server is not
/// asked. The state is the muted public uids (friend codes, never account
/// ids), oldest first, kept in preferences and bounded to [maxEntries]
/// (muting again moves a player to the newest end; the oldest drop off).
class MutedPlayersController extends Notifier<Set<String>> {
  static const int maxEntries = 200;

  PreferencesStore get _prefs => ref.read(preferencesStoreProvider);

  @override
  Set<String> build() => Set.unmodifiable(_read());

  Iterable<String> _read() {
    final raw = ref
        .read(preferencesStoreProvider)
        .getString(PrefKeys.mutedPlayers);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      final uids = list.whereType<String>().where((u) => u.isNotEmpty);
      final kept = uids.toList();
      return kept.length > maxEntries
          ? kept.sublist(kept.length - maxEntries)
          : kept;
    } on FormatException {
      return const [];
    }
  }

  bool isMuted(String uid) => state.contains(uid);

  /// Mutes [uid] (or unmutes it when [muted] is false) and persists.
  Future<void> setMuted(String uid, {required bool muted}) async {
    if (uid.isEmpty) return;
    final next = state.where((u) => u != uid).toList();
    if (muted) next.add(uid);
    final kept = next.length > maxEntries
        ? next.sublist(next.length - maxEntries)
        : next;
    state = Set.unmodifiable(kept);
    await _prefs.setString(PrefKeys.mutedPlayers, jsonEncode(kept));
  }
}

final mutedPlayersProvider =
    NotifierProvider<MutedPlayersController, Set<String>>(
      MutedPlayersController.new,
    );
