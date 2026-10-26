import 'package:localization_doctor/src/parsers/icu_parser.dart';
import 'package:test/test.dart';

void main() {
  group('parseIcuMessage', () {
    test('plain text has no arguments', () {
      final r = parseIcuMessage('Hello world');
      expect(r.isValid, isTrue);
      expect(r.arguments, isEmpty);
    });

    test('simple placeholders, with whitespace', () {
      final r = parseIcuMessage('Hi {name}, you have { count } new');
      expect(r.arguments, {
        'name': IcuArgumentKind.simple,
        'count': IcuArgumentKind.simple,
      });
    });

    test('plural with nested placeholder', () {
      final r = parseIcuMessage(
        '{count, plural, =0{none} =1{one} other{{count} items for {user}}}',
      );
      expect(r.isValid, isTrue);
      expect(r.arguments, {
        'count': IcuArgumentKind.plural,
        'user': IcuArgumentKind.simple,
      });
      expect(r.warnings, isEmpty);
    });

    test('select and nested plural', () {
      final r = parseIcuMessage(
        '{gender, select, male{{n, plural, one{He has one} other{He has {n}}}}'
        ' other{They}}',
      );
      expect(r.isValid, isTrue);
      expect(r.arguments['gender'], IcuArgumentKind.select);
      expect(r.arguments['n'], IcuArgumentKind.plural);
    });

    test('date and time arguments', () {
      final r = parseIcuMessage('On {day, date, yMMMd} at {t, time, Hm}');
      expect(r.arguments, {
        'day': IcuArgumentKind.date,
        't': IcuArgumentKind.time,
      });
    });

    test('missing other case is a warning, not an error', () {
      final r = parseIcuMessage('{n, plural, =1{one}}');
      expect(r.isValid, isTrue);
      expect(r.warnings.single.message, contains("no 'other' case"));
    });

    final errors = <String, String>{
      'Hello {name': "Unclosed '{'",
      'Hello }': "Unmatched '}'",
      'Hello {}': 'Expected a placeholder name',
      '{n, plural, other{x}': "Unclosed '{'",
      '{n, plural}': "Expected ','",
      '{n, plural, }': 'has no cases',
      '{n, currency}': "Unknown argument type 'currency'",
      '{n, plural, other x}': "Expected '{'",
      '{a b}': "Expected ',' or '}'",
    };
    errors.forEach((message, expected) {
      test('syntax error: $message', () {
        final r = parseIcuMessage(message);
        expect(r.isValid, isFalse);
        expect(r.errors.single.message, contains(expected));
      });
    });

    group('use-escaping', () {
      test('quoted braces are literal', () {
        final r = parseIcuMessage(
          "Use '{braces}' and {real}",
          useEscaping: true,
        );
        expect(r.isValid, isTrue);
        expect(r.arguments.keys, ['real']);
      });

      test('doubled quotes are a literal apostrophe', () {
        final r = parseIcuMessage("Isn''t it {x}?", useEscaping: true);
        expect(r.isValid, isTrue);
        expect(r.arguments.keys, ['x']);
      });

      test('unmatched quote is an error', () {
        final r = parseIcuMessage("It's {x}", useEscaping: true);
        expect(r.errors.single.message, contains('Unmatched single quote'));
      });

      test('without escaping, apostrophes are plain text', () {
        final r = parseIcuMessage("It's {x}");
        expect(r.isValid, isTrue);
        expect(r.arguments.keys, ['x']);
      });
    });

    group('relax-syntax', () {
      test('braces that do not start a known placeholder are literal', () {
        final r = parseIcuMessage(
          'Set {not a placeholder} to {value} }',
          relaxedPlaceholders: {'value'},
        );
        expect(r.isValid, isTrue);
        expect(r.arguments.keys, ['value']);
      });

      test('the same text is an error in strict mode', () {
        expect(
          parseIcuMessage('Set {not a placeholder} to {value}').isValid,
          isFalse,
        );
      });
    });
  });

  group('extractPatternPlaceholders', () {
    final defaultPattern = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

    test('extracts named placeholders', () {
      final r = extractPatternPlaceholders(
        'Hi {name}, {count}',
        defaultPattern,
      );
      expect(r.named, {'name', 'count'});
      expect(r.positionalCount, 0);
    });

    test('backslash-escaped braces are literal', () {
      final r = extractPatternPlaceholders(
        r'Literal \{name} and {x}',
        defaultPattern,
      );
      expect(r.named, {'x'});
    });

    test('literal braces that do not match the pattern are ignored', () {
      final r = extractPatternPlaceholders(
        'Use {} or { spaced }',
        defaultPattern,
      );
      expect(r.named, isEmpty);
      expect(r.positionalCount, 0);
    });

    test('optional group counts positional placeholders', () {
      final r = extractPatternPlaceholders(
        '{} and {} and {name}',
        RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)?\}'),
      );
      expect(r.positionalCount, 2);
      expect(r.named, {'name'});
    });

    test('custom double-brace pattern', () {
      final r = extractPatternPlaceholders(
        'Hello {{user}}',
        RegExp(r'\{\{\s*(\w+)\s*\}\}'),
      );
      expect(r.named, {'user'});
    });
  });
}
