import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/identity/player_id.dart';

void main() {
  group('PlayerId', () {
    test('keeps provided value', () {
      final id = PlayerId('player-1');
      expect(id.value, 'player-1');
      expect(id.rawValue, 'player-1');
      expect(id.toString(), 'player-1');
    });

    test('trims surrounding whitespace', () {
      final id = PlayerId('  player-1  ');
      expect(id.value, 'player-1');
    });

    test('rejects empty values', () {
      expect(() => PlayerId(''), throwsArgumentError);
      expect(() => PlayerId('   '), throwsArgumentError);
    });

    test('generates unique identifiers', () {
      final first = PlayerId.generate();
      final second = PlayerId.generate();
      expect(first, isNot(equals(second)));
      expect(first.value, isNotEmpty);
    });

    test('equality is value based', () {
      expect(PlayerId('a'), PlayerId('a'));
      expect(PlayerId('a'), isNot(PlayerId('b')));
      expect(PlayerId('a').hashCode, PlayerId('a').hashCode);
    });

    test('isSameAs and isDifferentFrom agree with equality', () {
      final a = PlayerId('a');
      final b = PlayerId('b');
      expect(a.isSameAs(PlayerId('a')), isTrue);
      expect(a.isDifferentFrom(b), isTrue);
    });

    test('isValid validates strings', () {
      expect(PlayerId.isValid('x'), isTrue);
      expect(PlayerId.isValid(' '), isFalse);
      expect(PlayerId.isValid(''), isFalse);
    });

    test('parse and fromJson round trip', () {
      expect(PlayerId.parse('p1').value, 'p1');
      expect(PlayerId.fromJson('p2').value, 'p2');
      expect(PlayerId('p3').toJson(), 'p3');
      expect(() => PlayerId.fromJson(42), throwsFormatException);
    });

    test('compareTo orders by value', () {
      final ids = [PlayerId('c'), PlayerId('a'), PlayerId('b')]..sort();
      expect(ids.map((id) => id.value), ['a', 'b', 'c']);
    });

    test('isEmpty and isNotEmpty reflect value', () {
      expect(PlayerId('x').isNotEmpty, isTrue);
      expect(PlayerId('x').isEmpty, isFalse);
    });
  });
}
