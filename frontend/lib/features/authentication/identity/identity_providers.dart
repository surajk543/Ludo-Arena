import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/app_info.dart';
import '../../../core/network/api_models.dart';
import 'apple_identity_client.dart';
import 'facebook_identity_client.dart';
import 'google_identity_client.dart';
import 'identity_provider_client.dart';

export 'identity_provider_client.dart';

/// The identity provider adapters, keyed by provider (overridable in tests).
final identityProviderClientsProvider =
    Provider<Map<LinkedProvider, IdentityProviderClient>>((ref) {
      final config = ref.watch(appConfigProvider);
      final platform = ref.watch(appInfoProvider).platform;
      return {
        LinkedProvider.google: GoogleIdentityClient(
          config: config,
          platform: platform,
        ),
        LinkedProvider.facebook: FacebookIdentityClient(config: config),
        LinkedProvider.apple: AppleIdentityClient(
          config: config,
          platform: platform,
        ),
      };
    });

/// Providers to offer on login / Save Progress screens, in display order
/// (Apple first on iOS per platform convention).
final availableSignInProvidersProvider = Provider<List<LinkedProvider>>((ref) {
  final clients = ref.watch(identityProviderClientsProvider);
  final ios = ref.watch(appInfoProvider).isIOS;
  final order = ios
      ? const [
          LinkedProvider.apple,
          LinkedProvider.google,
          LinkedProvider.facebook,
        ]
      : const [
          LinkedProvider.google,
          LinkedProvider.facebook,
          LinkedProvider.apple,
        ];
  return [
    for (final p in order)
      if (clients[p]?.isAvailable ?? false) p,
  ];
});
