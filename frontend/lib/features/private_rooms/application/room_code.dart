import 'package:flutter/services.dart';

/// Private room codes: 6 characters from `A-Z 2-9` without the ambiguous
/// `I`, `O`, `0` and `1`. Case-insensitive; always shown upper-case and LTR.
abstract final class RoomCode {
  static const int length = 6;

  /// Allowed alphabet (32 symbols).
  static const String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static final RegExp pattern = RegExp(r'^[A-HJ-NP-Z2-9]{6}$');
  static final RegExp _separators = RegExp(r'[\s\-_.·]');

  /// Upper-cases and strips spaces / dashes (as typed or pasted).
  static String normalize(String raw) =>
      raw.replaceAll(_separators, '').toUpperCase();

  /// True for a complete, well-formed code (after [normalize]).
  static bool isValid(String raw) => pattern.hasMatch(normalize(raw));

  /// Keeps only allowed characters, up to [length].
  static String sanitize(String raw) {
    final buffer = StringBuffer();
    for (final ch in normalize(raw).split('')) {
      if (alphabet.contains(ch)) buffer.write(ch);
      if (buffer.length == length) break;
    }
    return buffer.toString();
  }

  /// Whether [raw] contains characters that can never be part of a code
  /// (e.g. `O`, `0`, `I`, `1`, symbols).
  static bool hasInvalidCharacters(String raw) =>
      normalize(raw).split('').any((ch) => !alphabet.contains(ch));
}

/// Input formatter for the code field: upper-cases, drops separators and
/// characters outside [RoomCode.alphabet], and caps the length at 6. Works
/// for typing and pasting.
class RoomCodeInputFormatter extends TextInputFormatter {
  const RoomCodeInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = RoomCode.sanitize(newValue.text);
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
