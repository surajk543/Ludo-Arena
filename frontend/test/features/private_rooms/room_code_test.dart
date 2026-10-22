import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/features/private_rooms/application/room_code.dart';

void main() {
  group('RoomCode', () {
    test('alphabet is A-Z 2-9 without I, O, 0, 1', () {
      expect(RoomCode.alphabet.length, 32);
      for (final ch in ['I', 'O', '0', '1']) {
        expect(RoomCode.alphabet.contains(ch), isFalse, reason: ch);
      }
    });

    test('normalize upper-cases and strips separators', () {
      expect(RoomCode.normalize(' k7q-2mx '), 'K7Q2MX');
      expect(RoomCode.normalize('k7 q2 mx'), 'K7Q2MX');
    });

    test('valid codes are case-insensitive and exactly 6 characters', () {
      expect(RoomCode.isValid('K7Q2MX'), isTrue);
      expect(RoomCode.isValid('k7q2mx'), isTrue);
      expect(RoomCode.isValid('K7Q2M'), isFalse);
      expect(RoomCode.isValid('K7Q2MXA'), isFalse);
      expect(RoomCode.isValid('K7Q2MO'), isFalse, reason: 'O excluded');
      expect(RoomCode.isValid('K7Q2M0'), isFalse, reason: '0 excluded');
      expect(RoomCode.isValid('K7Q2MI'), isFalse, reason: 'I excluded');
      expect(RoomCode.isValid('K7Q2M1'), isFalse, reason: '1 excluded');
    });

    test('sanitize keeps allowed characters only, max 6', () {
      expect(RoomCode.sanitize('ab0cdo1ef9xyz'), 'ABCDEF');
      expect(RoomCode.sanitize('k7q2mx99'), 'K7Q2MX');
      expect(RoomCode.hasInvalidCharacters('K7Q2M0'), isTrue);
      expect(RoomCode.hasInvalidCharacters('k7q-2mx'), isFalse);
    });
  });

  group('RoomCodeInputFormatter', () {
    const f = RoomCodeInputFormatter();
    TextEditingValue type(String text) => f.formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );

    test('auto upper-cases while typing', () {
      expect(type('k7q').text, 'K7Q');
    });

    test('drops excluded characters and caps the length (paste)', () {
      expect(type('k7-q2 mx').text, 'K7Q2MX');
      expect(type('O0I1abcdefgh').text, 'ABCDEF');
      expect(type('K7Q2MXZZ').selection.baseOffset, 6);
    });
  });
}
