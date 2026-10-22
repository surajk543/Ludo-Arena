/// Why a display name is rejected. Values mirror the server's
/// `invalid_name` `details.reason` (docs/rest-api.md, `PATCH /me`).
enum DisplayNameProblem {
  tooShort('too_short'),
  tooLong('too_long'),
  invalidCharacters('invalid_characters'),
  reserved('reserved'),

  /// Server-only (blocklist): never detected on the device.
  inappropriate('inappropriate');

  const DisplayNameProblem(this.reason);

  /// The server's `details.reason`.
  final String reason;

  /// The problem for a server `details.reason`, or null when unknown.
  static DisplayNameProblem? parse(Object? reason) {
    for (final p in values) {
      if (p.reason == reason) return p;
    }
    return null;
  }
}

/// Client-side mirror of the server's display-name rules, for instant
/// feedback only: the server stays authoritative (and also applies NFC
/// normalization and a blocklist the app does not ship).
///
/// - normalized: trimmed, whitespace runs collapsed to one space;
/// - 3–16 characters (Unicode code points, combining marks included);
/// - letters of any script (+ combining marks), digits, space, `_ . -`,
///   with at least one letter (no emoji or symbols);
/// - reserved: starts with "bot", or contains admin / moderator / support /
///   official / system / ludoarena (the product name) / ludoroyale (its
///   former name) — case-insensitive, ignoring spaces and `_ . -`.
abstract final class DisplayNameRules {
  static const int minLength = 3;
  static const int maxLength = 16;

  /// Words no name may contain (after [_squash]).
  static const List<String> reservedWords = [
    'admin',
    'moderator',
    'support',
    'official',
    'system',
    'ludoarena',
    'ludoroyale',
  ];

  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _allowed = RegExp(
    r'^[\p{L}\p{M}\p{Nd} _.\-]+$',
    unicode: true,
  );
  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);
  static final RegExp _separators = RegExp(r'[\s_.\-]');

  /// Trims and collapses whitespace, like the server (minus NFC).
  static String normalize(String raw) =>
      raw.trim().replaceAll(_whitespace, ' ');

  /// Length as the server counts it (code points of the normalized name).
  static int lengthOf(String raw) => normalize(raw).runes.length;

  /// The first rule [raw] breaks, or null when it looks valid.
  static DisplayNameProblem? validate(String raw) {
    final name = normalize(raw);
    final length = name.runes.length;
    if (length < minLength) return DisplayNameProblem.tooShort;
    if (length > maxLength) return DisplayNameProblem.tooLong;
    if (!_allowed.hasMatch(name) || !_letter.hasMatch(name)) {
      return DisplayNameProblem.invalidCharacters;
    }
    final squashed = _squash(name);
    if (squashed.startsWith('bot') || reservedWords.any(squashed.contains)) {
      return DisplayNameProblem.reserved;
    }
    return null;
  }

  /// Whether [a] and [b] are the same name once normalized.
  static bool sameName(String a, String b) => normalize(a) == normalize(b);

  static String _squash(String name) =>
      name.toLowerCase().replaceAll(_separators, '');
}
