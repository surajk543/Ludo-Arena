import 'package:flutter/foundation.dart';

import '../../../core/protocol/json_read.dart';
import '../../../core/protocol/models.dart' show PlayerPicture;

/// Why a player is reported (`POST /reports` `reason`).
enum ReportReason {
  cheating('cheating'),
  offensiveName('offensive_name'),
  abusiveBehavior('abusive_behavior'),
  leavingOrStalling('leaving_or_stalling'),
  other('other');

  const ReportReason(this.wire);

  /// Wire value; also the analytics `reason` parameter (a fixed enum).
  final String wire;

  static ReportReason parse(String raw) =>
      values.firstWhere((r) => r.wire == raw, orElse: () => other);
}

/// Moderation state of a report. Unknown (newer) values read as
/// [submitted].
enum ReportStatus {
  submitted,
  reviewing,
  actionTaken,
  dismissed;

  static ReportStatus parse(String raw) => switch (raw) {
    'reviewing' => reviewing,
    'action_taken' => actionTaken,
    'dismissed' => dismissed,
    _ => submitted,
  };
}

/// Public profile of a reported player.
@immutable
class ReportedPlayer {
  const ReportedPlayer({
    required this.uid,
    required this.name,
    this.avatar = 0,
    this.picture,
    this.level = 1,
  });

  factory ReportedPlayer.fromJson(Map<String, dynamic> j) => ReportedPlayer(
    uid: readString(j['uid']),
    name: readString(j['name']),
    avatar: readInt(j['avatar']),
    picture: PlayerPicture.tryParse(j['picture']),
    level: readInt(j['level'], 1),
  );

  /// Public uid. Never sent to analytics.
  final String uid;
  final String name;
  final int avatar;

  /// Store profile picture (null: the built-in [avatar]).
  final PlayerPicture? picture;
  final int level;
}

/// One of my reports (`GET /reports`, `POST /reports`).
@immutable
class PlayerReport {
  const PlayerReport({
    required this.id,
    required this.player,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.game = '',
    this.roomId = '',
    int? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  factory PlayerReport.fromJson(Map<String, dynamic> j) {
    final created = readInt(j['createdAt']);
    return PlayerReport(
      id: readString(j['id']),
      player: ReportedPlayer.fromJson(readMap(j['player'])),
      reason: ReportReason.parse(readString(j['reason'])),
      game: readString(j['game']),
      roomId: readString(j['roomId']),
      status: ReportStatus.parse(readString(j['status'])),
      createdAt: created,
      updatedAt: readInt(j['updatedAt'], created),
    );
  }

  static List<PlayerReport> listFrom(Object? raw) => List.unmodifiable(
    readList(raw).map((e) => PlayerReport.fromJson(readMap(e))),
  );

  final String id;
  final ReportedPlayer player;
  final ReportReason reason;

  /// `ludo` | `snakes_ladders`.
  final String game;
  final String roomId;
  final ReportStatus status;

  /// Server unix ms.
  final int createdAt;
  final int updatedAt;
}

/// The rolling 24 h report allowance (`Limit`).
@immutable
class ReportLimit {
  const ReportLimit({this.perDay = 2, int? remaining, this.resetsAt})
    : remaining = remaining ?? perDay;

  factory ReportLimit.fromJson(Map<String, dynamic> j) {
    final perDay = readInt(j['perDay'], 2);
    return ReportLimit(
      perDay: perDay,
      remaining: readInt(j['remaining'], perDay),
      resetsAt: readIntOrNull(j['resetsAt']),
    );
  }

  final int perDay;
  final int remaining;

  /// Server unix ms when a report becomes available again (null while
  /// reports remain).
  final int? resetsAt;

  bool get exhausted => remaining <= 0;
}

/// `GET /reports`: my reports, newest first, and today's allowance.
@immutable
class ReportsState {
  const ReportsState({
    this.reports = const [],
    this.limit = const ReportLimit(),
    this.blockedUids = const {},
  });

  factory ReportsState.fromJson(Map<String, dynamic> j) => ReportsState(
    reports: PlayerReport.listFrom(j['reports']),
    limit: ReportLimit.fromJson(readMap(j['limit'])),
  );

  final List<PlayerReport> reports;
  final ReportLimit limit;

  /// Players the server said I already reported (409 `already_reported`)
  /// even if that report is not in [reports] yet.
  final Set<String> blockedUids;

  static const Duration window = Duration(hours: 24);

  /// Whether I reported [uid] within the last 24 h (server clock [nowMs]).
  bool reportedRecently(String uid, int nowMs) =>
      blockedUids.contains(uid) ||
      reports.any(
        (r) =>
            r.player.uid == uid && nowMs - r.createdAt < window.inMilliseconds,
      );

  ReportsState copyWith({
    List<PlayerReport>? reports,
    ReportLimit? limit,
    Set<String>? blockedUids,
  }) => ReportsState(
    reports: reports ?? this.reports,
    limit: limit ?? this.limit,
    blockedUids: blockedUids ?? this.blockedUids,
  );

  /// Adds a server-confirmed [report] at the top and applies [limit].
  ReportsState add(PlayerReport report, ReportLimit limit) => copyWith(
    reports: List.unmodifiable([
      report,
      ...reports.where((r) => r.id != report.id),
    ]),
    limit: limit,
  );

  ReportsState block(String uid) =>
      copyWith(blockedUids: Set.unmodifiable({...blockedUids, uid}));
}
