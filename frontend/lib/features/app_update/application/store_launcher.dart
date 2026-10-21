import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the store page for an update (overridable in tests).
abstract interface class StoreLauncher {
  /// Returns false when the URL could not be opened.
  Future<bool> open(String url);
}

class UrlStoreLauncher implements StoreLauncher {
  const UrlStoreLauncher();

  @override
  Future<bool> open(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'market')) {
      return false;
    }
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

final storeLauncherProvider = Provider<StoreLauncher>(
  (ref) => const UrlStoreLauncher(),
);
