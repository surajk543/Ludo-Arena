import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens web pages (e.g. the legal notices) in the user's browser, outside
/// the app. Overridable in tests.
abstract interface class ExternalLinkLauncher {
  /// Opens [url] externally; returns false when it is not an http(s) URL or
  /// could not be opened.
  Future<bool> open(String url);
}

class UrlExternalLinkLauncher implements ExternalLinkLauncher {
  const UrlExternalLinkLauncher();

  /// Only absolute http(s) URLs with a host are opened.
  static Uri? parse(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !(uri.scheme == 'https' || uri.scheme == 'http') ||
        uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  @override
  Future<bool> open(String url) async {
    final uri = parse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

final externalLinkLauncherProvider = Provider<ExternalLinkLauncher>(
  (ref) => const UrlExternalLinkLauncher(),
);
