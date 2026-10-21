import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Installed app identity, sent as `X-App-Platform/Version/Build` and to
/// `GET /app/config`.
@immutable
class AppInfo {
  const AppInfo({
    required this.platform,
    required this.version,
    required this.build,
  });

  /// `android` | `ios`.
  final String platform;

  /// Semantic version, e.g. `1.0.0` (no `-suffix`/`+build`).
  final String version;

  /// Positive build number.
  final int build;

  bool get isIOS => platform == 'ios';
  bool get isAndroid => platform == 'android';

  /// `1.0.0 (1)` — wrap in LTR isolation when embedding in RTL text.
  String get display => '$version ($build)';

  Map<String, String> get headers => {
    'X-App-Platform': platform,
    'X-App-Version': version,
    'X-App-Build': '$build',
  };

  static String currentPlatform() {
    if (kIsWeb) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  /// Reads version/build via package_info_plus. Strips any pre-release or
  /// metadata suffix, which the backend rejects.
  static Future<AppInfo> load() async {
    final info = await PackageInfo.fromPlatform();
    return AppInfo(
      platform: currentPlatform(),
      version: sanitizeVersion(info.version),
      build: int.tryParse(info.buildNumber) ?? 1,
    );
  }

  static String sanitizeVersion(String raw) {
    final core = raw.split(RegExp(r'[-+ ]')).first.trim();
    final parts = core.split('.');
    final valid =
        parts.isNotEmpty &&
        parts.length <= 4 &&
        parts.every((p) => int.tryParse(p) != null);
    return valid ? core : '1.0.0';
  }
}

/// Overridden in `bootstrap.dart` with the loaded value (and in tests).
final appInfoProvider = Provider<AppInfo>(
  (ref) =>
      AppInfo(platform: AppInfo.currentPlatform(), version: '1.0.0', build: 1),
);
