import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:ludo_royale/features/social/application/muted_players.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A container over [prefs] (one per "app start" / match).
ProviderContainer _container(PreferencesStore prefs) {
  final c = ProviderContainer(
    overrides: [preferencesStoreProvider.overrideWithValue(prefs)],
  );
  addTearDown(c.dispose);
  return c;
}

Future<PreferencesStore> _prefs([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  return PreferencesStore(await SharedPreferences.getInstance());
}

void main() {
  test('mute and unmute persist across containers (later matches, '
      'app restarts)', () async {
    final prefs = await _prefs();
    final first = _container(prefs);
    expect(first.read(mutedPlayersProvider), isEmpty);
    final n = first.read(mutedPlayersProvider.notifier);
    await n.setMuted('u_ravi', muted: true);
    await n.setMuted('b_0a1b2c3d4e', muted: true);
    expect(n.isMuted('u_ravi'), isTrue);

    final second = _container(prefs);
    expect(second.read(mutedPlayersProvider), {'u_ravi', 'b_0a1b2c3d4e'});
    await second
        .read(mutedPlayersProvider.notifier)
        .setMuted('u_ravi', muted: false);
    expect(_container(prefs).read(mutedPlayersProvider), {'b_0a1b2c3d4e'});
    expect(prefs.getString(PrefKeys.mutedPlayers), '["b_0a1b2c3d4e"]');
  });

  test('keeps the 200 most recently muted players', () async {
    final prefs = await _prefs();
    final c = _container(prefs);
    final n = c.read(mutedPlayersProvider.notifier);
    for (var i = 0; i < 205; i++) {
      await n.setMuted('u_$i', muted: true);
    }
    // Muting again makes a player the newest.
    await n.setMuted('u_5', muted: true);
    await n.setMuted('u_new', muted: true);
    final muted = c.read(mutedPlayersProvider);
    expect(muted, hasLength(MutedPlayersController.maxEntries));
    expect(muted.last, 'u_new');
    // u_0..u_4 dropped at 205; u_6 dropped when u_new came in.
    expect(muted, isNot(contains('u_4')));
    expect(muted, contains('u_5'));
    expect(muted, isNot(contains('u_6')));
    expect(muted, contains('u_7'));
    expect(_container(prefs).read(mutedPlayersProvider), muted);
  });

  test('a damaged or oversized stored list is read safely', () async {
    for (final (raw, expected) in [
      ('not json', <String>{}),
      ('{"u_1":true}', <String>{}),
      ('["u_1", 3, "", "u_2"]', {'u_1', 'u_2'}),
    ]) {
      final prefs = await _prefs({PrefKeys.mutedPlayers: raw});
      expect(
        _container(prefs).read(mutedPlayersProvider),
        expected,
        reason: raw,
      );
    }
    final big = List.generate(250, (i) => '"u_$i"').join(',');
    final prefs = await _prefs({PrefKeys.mutedPlayers: '[$big]'});
    final muted = _container(prefs).read(mutedPlayersProvider);
    expect(muted, hasLength(200));
    expect(muted.first, 'u_50');
  });
}
