import 'package:flutter/foundation.dart';

/// `mode` of `GET /app/config`.
enum PolicyMode {
  normal,
  optionalUpdate,
  forceUpdate,
  maintenance;

  static PolicyMode parse(String? raw) => switch (raw) {
    'optional_update' => optionalUpdate,
    'force_update' => forceUpdate,
    'maintenance' => maintenance,
    _ => normal,
  };

  String get wire => switch (this) {
    normal => 'normal',
    optionalUpdate => 'optional_update',
    forceUpdate => 'force_update',
    maintenance => 'maintenance',
  };
}

int _int(Object? v, [int d = 0]) => v is num ? v.toInt() : d;
String _str(Object? v) => v is String ? v : '';

/// Maintenance block of the policy.
@immutable
class MaintenanceInfo {
  const MaintenanceInfo({
    this.enabled = false,
    this.message = '',
    this.startsAtUtc,
    this.scheduledEndUtc,
  });

  final bool enabled;
  final String message;
  final DateTime? startsAtUtc;

  /// Estimated end (UTC). Always present it as an estimate.
  final DateTime? scheduledEndUtc;

  static DateTime? _date(Object? v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toUtc() : null;

  factory MaintenanceInfo.fromJson(Map<String, dynamic> j) => MaintenanceInfo(
    enabled: j['enabled'] == true,
    message: _str(j['message']),
    startsAtUtc: _date(j['startsAtUtc']),
    scheduledEndUtc: _date(j['scheduledEndUtc']),
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'message': message,
    'startsAtUtc': startsAtUtc?.toIso8601String(),
    'scheduledEndUtc': scheduledEndUtc?.toIso8601String(),
  };
}

/// Evaluated app policy from `GET /api/v1/app/config` (see
/// docs/app-version-policy.md). The server decides; the client only renders.
@immutable
class AppPolicy {
  const AppPolicy({
    required this.mode,
    this.configVersion = 0,
    this.environment = '',
    this.platform = '',
    this.installedVersion = '',
    this.installedBuild = 0,
    this.minimumSupportedVersion = '',
    this.minimumSupportedBuild = 0,
    this.latestVersion = '',
    this.latestBuild = 0,
    this.storeUrl = '',
    this.storeAvailable = false,
    this.title = '',
    this.message = '',
    this.optionalUpdateReminderHours = 24,
    this.maintenance = const MaintenanceInfo(),
    this.rulesVersion = 1,
    this.protocolVersion = 1,
    this.entryFees = const {},
    this.serverTime = 0,
  });

  final PolicyMode mode;
  final int configVersion;
  final String environment;
  final String platform;
  final String installedVersion;
  final int installedBuild;
  final String minimumSupportedVersion;
  final int minimumSupportedBuild;
  final String latestVersion;
  final int latestBuild;
  final String storeUrl;
  final bool storeAvailable;

  /// Optional server-localized title/message (empty → use app strings).
  final String title;
  final String message;
  final int optionalUpdateReminderHours;
  final MaintenanceInfo maintenance;
  final int rulesVersion;
  final int protocolVersion;

  /// Coin entry fee per game id (`ludo`, `snakes_ladders`).
  final Map<String, int> entryFees;
  final int serverTime;

  /// Store link usable for "Update now".
  bool get canOpenStore => storeAvailable && storeUrl.trim().isNotEmpty;

  int entryFeeFor(String game) => entryFees[game] ?? 0;

  factory AppPolicy.fromJson(Map<String, dynamic> j) => AppPolicy(
    mode: PolicyMode.parse(j['mode'] as String?),
    configVersion: _int(j['configVersion']),
    environment: _str(j['environment']),
    platform: _str(j['platform']),
    installedVersion: _str(j['installedVersion']),
    installedBuild: _int(j['installedBuild']),
    minimumSupportedVersion: _str(j['minimumSupportedVersion']),
    minimumSupportedBuild: _int(j['minimumSupportedBuild']),
    latestVersion: _str(j['latestVersion']),
    latestBuild: _int(j['latestBuild']),
    storeUrl: _str(j['storeUrl']),
    storeAvailable: j['storeAvailable'] == true,
    title: _str(j['title']),
    message: _str(j['message']),
    optionalUpdateReminderHours: _int(j['optionalUpdateReminderHours'], 24),
    maintenance: j['maintenance'] is Map
        ? MaintenanceInfo.fromJson(
            (j['maintenance'] as Map).cast<String, dynamic>(),
          )
        : const MaintenanceInfo(),
    rulesVersion: _int(j['rulesVersion'], 1),
    protocolVersion: _int(j['protocolVersion'], 1),
    entryFees: j['entryFees'] is Map
        ? {
            for (final e in (j['entryFees'] as Map).entries)
              if (e.key is String && e.value is num)
                e.key as String: (e.value as num).toInt(),
          }
        : const {},
    serverTime: _int(j['serverTime']),
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.wire,
    'configVersion': configVersion,
    'environment': environment,
    'platform': platform,
    'installedVersion': installedVersion,
    'installedBuild': installedBuild,
    'minimumSupportedVersion': minimumSupportedVersion,
    'minimumSupportedBuild': minimumSupportedBuild,
    'latestVersion': latestVersion,
    'latestBuild': latestBuild,
    'storeUrl': storeUrl,
    'storeAvailable': storeAvailable,
    'title': title,
    'message': message,
    'optionalUpdateReminderHours': optionalUpdateReminderHours,
    'maintenance': maintenance.toJson(),
    'rulesVersion': rulesVersion,
    'protocolVersion': protocolVersion,
    'entryFees': entryFees,
    'serverTime': serverTime,
  };
}
