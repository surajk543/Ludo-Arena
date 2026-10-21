import 'package:flutter/foundation.dart';

import '../../../core/protocol/json_read.dart';
import '../../../shared/widgets/cosmetic_names.dart' show cosmeticRarity;

/// Catalog kind of an item id (`ludo_board_royal` → `ludo_board`).
String kindOfItemId(String itemId) {
  for (final k in const ['ludo_board', 'snakes_board']) {
    if (itemId.startsWith('${k}_')) return k;
  }
  final i = itemId.indexOf('_');
  return i > 0 ? itemId.substring(0, i) : itemId;
}

/// `ItemRef` — a catalog item mentioned by rewards, milestones and grants.
@immutable
class ItemRef {
  const ItemRef({
    required this.id,
    required this.kind,
    this.name = '',
    this.rarity = 'common',
  });

  factory ItemRef.fromJson(Map<String, dynamic> j) {
    final id = readString(j['id']);
    return ItemRef(
      id: id,
      kind: readString(j['kind'], kindOfItemId(id)),
      name: readString(j['name']),
      rarity: readString(j['rarity'], cosmeticRarity(id).name),
    );
  }

  /// From a bare id (e.g. `progression.updated.unlocked`).
  factory ItemRef.fromId(String id) =>
      ItemRef(id: id, kind: kindOfItemId(id), rarity: cosmeticRarity(id).name);

  final String id;
  final String kind;

  /// Server English fallback name (display the localized name instead).
  final String name;
  final String rarity;

  static List<ItemRef> listFrom(Object? raw) =>
      List.unmodifiable(readList(raw).map((e) => ItemRef.fromJson(readMap(e))));

  @override
  bool operator ==(Object other) =>
      other is ItemRef &&
      other.id == id &&
      other.kind == kind &&
      other.rarity == rarity;

  @override
  int get hashCode => Object.hash(id, kind, rarity);
}

/// One level milestone of `GET /progression`.
@immutable
class Milestone {
  const Milestone({
    required this.level,
    required this.rewards,
    required this.reached,
  });

  factory Milestone.fromJson(Map<String, dynamic> j) => Milestone(
    level: readInt(j['level'], 1),
    rewards: ItemRef.listFrom(j['rewards']),
    reached: readBool(j['reached']),
  );

  final int level;
  final List<ItemRef> rewards;
  final bool reached;
}

/// Level/XP numbers shared by `GET /progression` and claim responses.
/// Progress bar = (xp − levelXp) / nextLevelXp (docs/progression.md).
mixin LevelNumbers {
  int get level;
  int get xp;
  int get levelXp;
  int get nextLevelXp;
  int get maxLevel => 50;

  bool get isMaxLevel => level >= maxLevel;

  /// XP earned inside the current level, clamped to 0..nextLevelXp.
  int get xpIntoLevel {
    final v = xp - levelXp;
    if (v < 0) return 0;
    return v > nextLevelXp ? nextLevelXp : v;
  }

  /// XP still needed for the next level (0 at max level).
  int get xpRemaining => isMaxLevel ? 0 : nextLevelXp - xpIntoLevel;

  /// 0..1; full at max level.
  double get fraction =>
      isMaxLevel || nextLevelXp <= 0 ? 1 : xpIntoLevel / nextLevelXp;
}

/// `GET /progression`.
@immutable
class ProgressionView with LevelNumbers {
  const ProgressionView({
    required this.level,
    required this.xp,
    required this.levelXp,
    required this.nextLevelXp,
    this.maxLevel = 50,
    this.title = 'title_rookie',
    this.milestones = const [],
  });

  factory ProgressionView.fromJson(Map<String, dynamic> j) => ProgressionView(
    level: readInt(j['level'], 1),
    xp: readInt(j['xp']),
    levelXp: readInt(j['levelXp']),
    nextLevelXp: readInt(j['nextLevelXp'], 100),
    maxLevel: readInt(j['maxLevel'], 50),
    title: readString(j['title'], 'title_rookie'),
    milestones: List.unmodifiable(
      readList(j['milestones']).map((m) => Milestone.fromJson(readMap(m))),
    ),
  );

  @override
  final int level;
  @override
  final int xp;
  @override
  final int levelXp;
  @override
  final int nextLevelXp;
  @override
  final int maxLevel;
  final String title;
  final List<Milestone> milestones;

  /// The first milestone not reached yet.
  Milestone? get nextMilestone {
    for (final m in milestones) {
      if (!m.reached) return m;
    }
    return null;
  }

  ProgressionView copyWith({int? xp}) => ProgressionView(
    level: level,
    xp: xp ?? this.xp,
    levelXp: levelXp,
    nextLevelXp: nextLevelXp,
    maxLevel: maxLevel,
    title: title,
    milestones: milestones,
  );
}

/// `progression` object of a mission claim response.
@immutable
class ProgressSnapshot with LevelNumbers {
  const ProgressSnapshot({
    required this.level,
    required this.xp,
    required this.levelXp,
    required this.nextLevelXp,
    this.xpGained = 0,
    this.levelUp = false,
  });

  factory ProgressSnapshot.fromJson(Map<String, dynamic> j) => ProgressSnapshot(
    level: readInt(j['level'], 1),
    xp: readInt(j['xp']),
    levelXp: readInt(j['levelXp']),
    nextLevelXp: readInt(j['nextLevelXp'], 100),
    xpGained: readInt(j['xpGained']),
    levelUp: readBool(j['levelUp']),
  );

  @override
  final int level;
  @override
  final int xp;
  @override
  final int levelXp;
  @override
  final int nextLevelXp;
  final int xpGained;
  final bool levelUp;
}
