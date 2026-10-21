import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/features/profile/domain/display_name.dart';

void main() {
  group('normalize', () {
    test('trims and collapses whitespace', () {
      expect(DisplayNameRules.normalize('  Rahul \t  K  '), 'Rahul K');
      expect(DisplayNameRules.normalize('A  B'), 'A B');
      expect(DisplayNameRules.normalize('   '), '');
    });

    test('length counts code points of the normalized name', () {
      expect(DisplayNameRules.lengthOf('  Asha  '), 4);
      // र ा ह ु ल: combining vowel signs count.
      expect(DisplayNameRules.lengthOf('राहुल'), 5);
    });

    test('sameName ignores outer and repeated whitespace', () {
      expect(DisplayNameRules.sameName(' Asha ', 'Asha'), isTrue);
      expect(DisplayNameRules.sameName('Asha', 'asha'), isFalse);
    });
  });

  group('validate', () {
    final cases = <String, DisplayNameProblem?>{
      // Accepted: letters of any script, digits, space, _ . -
      'Asha': null,
      'Rahul_K.99': null,
      'Mary-Jane': null,
      'राहुल': null,
      'राहुल शर्मा': null,
      'علی رضا': null,
      'محمد علي': null,
      'Budi Santoso': null,
      'Siti.Nur_2': null,
      'José': null,
      'Zoë 7': null,
      'Abc': null,
      'Abcdefghijklmnop': null, // exactly 16
      // Length
      '': DisplayNameProblem.tooShort,
      '   ': DisplayNameProblem.tooShort,
      'Ab': DisplayNameProblem.tooShort,
      '  Ab  ': DisplayNameProblem.tooShort,
      'Abcdefghijklmnopq': DisplayNameProblem.tooLong,
      // Characters
      'Raj 😎': DisplayNameProblem.invalidCharacters,
      'Raj\$\$': DisplayNameProblem.invalidCharacters,
      'Raj@home': DisplayNameProblem.invalidCharacters,
      '<b>Raj</b>': DisplayNameProblem.invalidCharacters,
      '12345': DisplayNameProblem.invalidCharacters, // no letter
      '___': DisplayNameProblem.invalidCharacters,
      // Reserved
      'Bot Raj': DisplayNameProblem.reserved,
      'bot': DisplayNameProblem.reserved,
      'B.o.t_Raj': DisplayNameProblem.reserved,
      'Botanist': DisplayNameProblem.reserved, // starts with "bot"
      'admin': DisplayNameProblem.reserved,
      'Super ADMIN': DisplayNameProblem.reserved,
      'a.d.m.i.n': DisplayNameProblem.reserved,
      'TheModerator': DisplayNameProblem.reserved,
      'Support Team': DisplayNameProblem.reserved,
      'Official Raj': DisplayNameProblem.reserved,
      'System': DisplayNameProblem.reserved,
      'Ludo Royale': DisplayNameProblem.reserved,
      'ludo_royale_fan': DisplayNameProblem.reserved,
      'Robot': null, // "bot" only reserved as a prefix
    };
    cases.forEach((name, expected) {
      test('"$name" → ${expected?.reason ?? 'ok'}', () {
        expect(DisplayNameRules.validate(name), expected);
      });
    });
  });

  test('server reasons parse to problems', () {
    for (final p in DisplayNameProblem.values) {
      expect(DisplayNameProblem.parse(p.reason), p);
    }
    expect(DisplayNameProblem.parse('something_new'), isNull);
    expect(DisplayNameProblem.parse(null), isNull);
  });
}
