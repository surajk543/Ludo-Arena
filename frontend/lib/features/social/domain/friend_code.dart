/// Why a typed friend code was rejected before calling the server.
enum FriendCodeProblem { empty, invalid, own }

/// Friend codes are the public uid (`u_` + lowercase letters/digits),
/// case-insensitive on the server.
abstract final class FriendCode {
  static const String prefix = 'u_';
  static final RegExp _valid = RegExp(r'^u_[a-z0-9]{4,32}$');
  static final RegExp _separators = RegExp(r'[\s\-.·]');

  /// Readable display form: `u_3f9a1c2b7d4e` → `u_3f9a 1c2b 7d4e`. Always
  /// render it LTR. Copy/share the raw code, not this.
  static String format(String uid) {
    if (!uid.startsWith(prefix)) return uid;
    final body = uid.substring(prefix.length);
    final groups = <String>[];
    for (var i = 0; i < body.length; i += 4) {
      groups.add(body.substring(i, i + 4 > body.length ? body.length : i + 4));
    }
    return '$prefix${groups.join(' ')}';
  }

  /// Normalizes user input: trims, drops spaces/dashes/dots, lowercases and
  /// adds the `u_` prefix when missing.
  static String normalize(String raw) {
    var s = raw.trim().toLowerCase().replaceAll(_separators, '');
    if (s.isEmpty) return s;
    if (!s.startsWith(prefix)) {
      s = '$prefix${s.replaceFirst(RegExp(r'^_+'), '')}';
    }
    return s;
  }

  static bool isValid(String normalized) => _valid.hasMatch(normalized);

  /// Validates [raw] input against the format and the user's own [myUid].
  static FriendCodeProblem? validate(String raw, {String? myUid}) {
    final code = normalize(raw);
    if (code.isEmpty) return FriendCodeProblem.empty;
    if (!isValid(code)) return FriendCodeProblem.invalid;
    if (myUid != null && code == myUid.toLowerCase()) {
      return FriendCodeProblem.own;
    }
    return null;
  }
}
