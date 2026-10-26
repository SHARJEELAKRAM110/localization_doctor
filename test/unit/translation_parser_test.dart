import 'package:localization_doctor/localization_doctor.dart';
import 'package:localization_doctor/src/models/translation.dart';
import 'package:localization_doctor/src/parsers/translation_parser.dart';
import 'package:test/test.dart';

ParsedTranslationFile arb(String content) => parseArbFile(
  content: content,
  path: 'lib/l10n/app_en.arb',
  locale: 'en',
  bundle: 'lib/l10n/app_*.arb',
);

ParsedTranslationFile json(String content, {String separator = '.'}) =>
    parseJsonTranslationFile(
      content: content,
      path: 'assets/translations/en.json',
      locale: 'en',
      bundle: 'assets/translations/*.json',
      separator: separator,
    );

void main() {
  group('ARB', () {
    test('parses messages, metadata and @@locale', () {
      final parsed = arb('''
{
  "@@locale": "en",
  "@@last_modified": "2026-01-01",
  "hello": "Hello {name}",
  "@hello": {
    "description": "Greeting",
    "placeholders": {"name": {"type": "String", "format": "x"}}
  },
  "bye": "Bye"
}''');
      expect(parsed.diagnostics, isEmpty);
      final file = parsed.file;
      expect(file.declaredLocale, 'en');
      expect(file.entries.keys, ['hello', 'bye']);
      expect(file.entries['hello']!.value, 'Hello {name}');
      expect(file.entries['hello']!.location.line, 4);
      final placeholder = file.metadata['hello']!.placeholders!['name']!;
      expect(placeholder.type, 'String');
      expect(placeholder.format, 'x');
    });

    test('metadata entries are not counted as messages', () {
      final file = arb('{"a": "A", "@a": {}, "@@locale": "en"}').file;
      expect(file.entries.keys, ['a']);
    });

    test('detects duplicate message keys with both locations', () {
      final parsed = arb('{\n  "title": "One",\n  "title": "Two"\n}');
      final dup = parsed.diagnostics.single;
      expect(dup.code, DiagnosticCode.duplicateKey);
      expect(dup.severity, Severity.error);
      expect(dup.key, 'title');
      expect(dup.location!.line, 3);
      expect(dup.relatedLocations.single.line, 2);
      // The last value wins, matching jsonDecode and gen-l10n.
      expect(parsed.file.entries['title']!.value, 'Two');
    });

    test('detects duplicates inside metadata and placeholders', () {
      final parsed = arb('''
{
  "a": "{x}",
  "@a": {
    "description": "one",
    "description": "two",
    "placeholders": {"x": {}, "x": {"type": "int"}}
  }
}''');
      final keys = parsed.diagnostics
          .where((d) => d.code == DiagnosticCode.duplicateKey)
          .map((d) => d.key)
          .toList();
      expect(keys, ['@a.description', '@a.placeholders.x']);
    });

    test('reports non-string message values', () {
      final parsed = arb('{"count": 3, "list": ["a"]}');
      expect(
        parsed.diagnostics.map((d) => d.code),
        everyElement(DiagnosticCode.invalidValueType),
      );
      expect(parsed.diagnostics, hasLength(2));
      expect(parsed.file.entries['count']!.kind, EntryKind.invalid);
      expect(parsed.file.entries['count']!.valueType, 'number');
    });

    test('reports metadata that is not an object', () {
      final parsed = arb('{"a": "A", "@a": "oops"}');
      expect(parsed.diagnostics.single.code, DiagnosticCode.arbMetadata);
    });

    test('malformed ARB is reported with line and column', () {
      final parsed = arb('{\n  "a": "A"\n  "b": "B"\n}');
      expect(parsed.file.isValid, isFalse);
      final d = parsed.diagnostics.single;
      expect(d.code, DiagnosticCode.invalidFile);
      expect(d.location!.line, 3);
      expect(d.location!.column, 3);
      expect(d.message, startsWith('Malformed JSON'));
    });

    test('root must be an object', () {
      final parsed = arb('["a"]');
      expect(parsed.diagnostics.single.code, DiagnosticCode.invalidFile);
      expect(parsed.diagnostics.single.message, contains('found array'));
    });
  });

  group('JSON', () {
    test('flattens nested objects into canonical dotted keys', () {
      final parsed = json('''
{
  "home": {"title": "Home", "menu": {"open": "Open"}},
  "ok": "OK"
}''');
      expect(parsed.diagnostics, isEmpty);
      expect(parsed.file.entries.keys, ['home.title', 'home.menu.open', 'ok']);
      expect(parsed.file.objectPaths.keys, ['home', 'home.menu']);
    });

    test('supports a custom key separator', () {
      final parsed = json('{"a": {"b": "x"}}', separator: ':');
      expect(parsed.file.entries.keys, ['a:b']);
    });

    test('detects duplicate keys at every nesting level', () {
      final parsed = json('''
{
  "top": "1",
  "top": "2",
  "home": {
    "title": "a",
    "title": "b",
    "deep": {"x": "1", "x": "2"}
  }
}''');
      final dups = parsed.diagnostics
          .where((d) => d.code == DiagnosticCode.duplicateKey)
          .map((d) => d.key)
          .toList();
      expect(dups, ['top', 'home.title', 'home.deep.x']);
    });

    test('reports flat dotted keys that collide with nested keys', () {
      final parsed = json('{"home": {"title": "A"}, "home.title": "B"}');
      final d = parsed.diagnostics.single;
      expect(d.code, DiagnosticCode.structureMismatch);
      expect(d.key, 'home.title');
      expect(d.message, contains('ambiguous'));
    });

    test('flat dotted keys without collisions are accepted', () {
      final parsed = json('{"home.title": "A", "home.body": "B"}');
      expect(parsed.diagnostics, isEmpty);
      expect(parsed.file.entries.keys, ['home.title', 'home.body']);
    });

    test('reports invalid value types', () {
      final parsed = json('{"a": null, "b": 1, "c": true, "d": []}');
      expect(parsed.diagnostics, hasLength(4));
      expect(parsed.diagnostics.map((d) => d.code).toSet(), {
        DiagnosticCode.invalidValueType,
      });
    });

    test('malformed JSON is reported, not thrown', () {
      final parsed = json('{"a": "b",}');
      expect(parsed.file.isValid, isFalse);
      expect(parsed.diagnostics.single.message, contains('Trailing commas'));
    });
  });
}
