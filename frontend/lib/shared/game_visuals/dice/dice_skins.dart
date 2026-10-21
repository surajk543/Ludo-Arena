import 'package:flutter/material.dart';

/// Dice skin ids from `docs/cosmetics-catalog.md`.
abstract final class DiceSkins {
  static const classic = 'dice_classic';
  static const neon = 'dice_neon';
  static const golden = 'dice_golden';
  static const autumn = 'dice_autumn';

  static const all = [classic, neon, golden, autumn];

  /// Known id or the starter skin.
  static String resolve(String? id) => all.contains(id) ? id! : classic;
}

/// Special decoration a dice skin draws on its faces.
enum DiceMotif {
  /// Plain faces.
  none,

  /// Subtle leaf veins on every face and a maple leaf instead of the single
  /// pip on face 1.
  autumnLeaves,
}

/// Immutable visual description of a dice skin for one brightness.
@immutable
class DiceStyle {
  const DiceStyle({
    required this.id,
    required this.faceLight,
    required this.faceDark,
    required this.edge,
    required this.outline,
    required this.pip,
    required this.pipHighlight,
    required this.onePip,
    this.pipGlow,
    this.edgeGlow,
    this.rim,
    this.veins,
    this.motif = DiceMotif.none,
    this.alternatePip,
  });

  /// Resolves [id] (unknown → classic) for [brightness]. [accent] tints the
  /// neon edge glow when provided.
  factory DiceStyle.resolve(
    String? id, {
    required Brightness brightness,
    Color? accent,
  }) {
    final dark = brightness == Brightness.dark;
    switch (DiceSkins.resolve(id)) {
      case DiceSkins.neon:
        final glow = accent ?? const Color(0xFF2EF2FF);
        return DiceStyle(
          id: DiceSkins.neon,
          faceLight: const Color(0xFF23254A),
          faceDark: const Color(0xFF0A0B17),
          edge: const Color(0xFF15162B),
          outline: Color.lerp(glow, Colors.black, 0.35)!,
          pip: const Color(0xFF2EF2FF),
          pipHighlight: const Color(0xFFE6FDFF),
          onePip: const Color(0xFFFF3DDB),
          alternatePip: const Color(0xFFFF3DDB),
          pipGlow: const Color(0xFF2EF2FF),
          edgeGlow: glow,
          rim: glow.withValues(alpha: 0.9),
        );
      case DiceSkins.golden:
        return DiceStyle(
          id: DiceSkins.golden,
          faceLight: dark ? const Color(0xFFF7DE8E) : const Color(0xFFFFEDB0),
          faceDark: dark ? const Color(0xFFB8860B) : const Color(0xFFD29F22),
          edge: const Color(0xFF8C620E),
          outline: const Color(0xFF5A3D05),
          pip: const Color(0xFF4A2A0A),
          pipHighlight: const Color(0xFF8A5A1E),
          onePip: const Color(0xFF6E1414),
          rim: const Color(0xFFFFF6D6),
        );
      case DiceSkins.autumn:
        return DiceStyle(
          id: DiceSkins.autumn,
          faceLight: dark ? const Color(0xFFF09A4A) : const Color(0xFFF9AE5E),
          faceDark: dark ? const Color(0xFFB9501E) : const Color(0xFFD9622B),
          edge: const Color(0xFF8E3812),
          outline: const Color(0xFF5C230A),
          pip: const Color(0xFFFFF3DC),
          pipHighlight: const Color(0xFFFFFFFF),
          onePip: const Color(0xFFFFF3DC),
          veins: const Color(0xFF9E4318),
          motif: DiceMotif.autumnLeaves,
        );
      default:
        return DiceStyle(
          id: DiceSkins.classic,
          faceLight: dark ? const Color(0xFFF4EFE4) : const Color(0xFFFFFDF7),
          faceDark: dark ? const Color(0xFFD3C8B1) : const Color(0xFFEDE3CD),
          edge: dark ? const Color(0xFFB7A98C) : const Color(0xFFD4C6A8),
          outline: dark ? const Color(0xFF0E0F14) : const Color(0xFF6E6250),
          pip: const Color(0xFF2B2B33),
          pipHighlight: const Color(0xFF5A5A66),
          onePip: const Color(0xFFC0262D),
        );
    }
  }

  final String id;

  /// Face gradient (top-left → bottom-right in face space).
  final Color faceLight;
  final Color faceDark;

  /// Bevel between faces.
  final Color edge;

  /// Thin contrast outline around the silhouette.
  final Color outline;

  /// Pip fill and its inner highlight.
  final Color pip;
  final Color pipHighlight;

  /// Color of the single pip on face 1.
  final Color onePip;

  /// Optional alternate pip color used on even faces (neon).
  final Color? alternatePip;

  /// Glow halo around pips (neon).
  final Color? pipGlow;

  /// Glow around the whole die (neon).
  final Color? edgeGlow;

  /// Bright rim stroke on each face (golden, neon).
  final Color? rim;

  /// Vein stroke color for [DiceMotif.autumnLeaves].
  final Color? veins;

  final DiceMotif motif;

  @override
  bool operator ==(Object other) =>
      other is DiceStyle &&
      other.id == id &&
      other.faceLight == faceLight &&
      other.faceDark == faceDark &&
      other.edge == edge &&
      other.outline == outline &&
      other.pip == pip &&
      other.edgeGlow == edgeGlow;

  @override
  int get hashCode =>
      Object.hash(id, faceLight, faceDark, edge, outline, pip, edgeGlow);
}
