import 'dart:convert';

import 'package:localization_doctor/src/parsers/json_source_parser.dart';
import 'package:test/test.dart';

void main() {
  group('parseJsonWithPositions', () {
    test('keeps every member of a duplicated key, in order', () {
      final root = parseJsonWithPositions('{"a": "1", "a": "2"}') as JsonObject;
      expect(root.members.map((m) => m.key), ['a', 'a']);
      expect(root.members.map((m) => (m.value as JsonString).value), [
        '1',
        '2',
      ]);
      // Proves the problem this parser solves: jsonDecode loses the first.
      expect(jsonDecode('{"a": "1", "a": "2"}'), {'a': '2'});
    });

    test('reports 1-based line and column of keys', () {
      final root =
          parseJsonWithPositions('{\n  "first": 1,\n    "second": 2\n}')
              as JsonObject;
      expect(root.members[0].keyPosition.line, 2);
      expect(root.members[0].keyPosition.column, 3);
      expect(root.members[1].keyPosition.line, 3);
      expect(root.members[1].keyPosition.column, 5);
    });

    test('treats CRLF line endings as one line break', () {
      final root =
          parseJsonWithPositions('{\r\n"a": 1,\r\n"b": 2\r\n}') as JsonObject;
      expect(root.members[1].keyPosition.line, 3);
      expect(root.members[1].keyPosition.column, 1);
    });

    test('decodes escapes and unicode including surrogate pairs', () {
      final root =
          parseJsonWithPositions(r'{"s": "a\"b\\c\/d\nا😀"}') as JsonObject;
      expect((root.members.single.value as JsonString).value, 'a"b\\c/d\nا😀');
    });

    test('parses all value types', () {
      final root =
          parseJsonWithPositions(
                '{"n": -1.5e3, "t": true, "f": false, "z": null, "l": [1, {}]}',
              )
              as JsonObject;
      expect(root.members.map((m) => m.value.typeName), [
        'number',
        'boolean',
        'boolean',
        'null',
        'array',
      ]);
      expect((root.members.first.value as JsonNumber).value, -1500);
    });

    test('ignores a leading byte order mark', () {
      expect(parseJsonWithPositions('﻿{}'), isA<JsonObject>());
    });

    final invalid = <String, String>{
      'empty file': '',
      'trailing comma in object': '{"a": 1,}',
      'trailing comma in array': '[1,]',
      'missing comma': '{"a": 1 "b": 2}',
      'single quotes': "{'a': 1}",
      'comments': '{"a": 1 // note\n}',
      'unterminated string': '{"a": "b}',
      'unquoted key': '{a: 1}',
      'garbage after value': '{} x',
      'leading zero': '{"a": 01}',
      'invalid escape': r'{"a": "\x"}',
      'raw control character': '{"a": "line\nbreak"}',
    };
    invalid.forEach((name, source) {
      test('rejects $name', () {
        expect(
          () => parseJsonWithPositions(source),
          throwsA(isA<JsonSyntaxException>()),
        );
      });
    });

    test('error position points at the problem', () {
      try {
        parseJsonWithPositions('{\n  "a": 1\n  "b": 2\n}');
        fail('expected an exception');
      } on JsonSyntaxException catch (e) {
        expect(e.position.line, 3);
        expect(e.position.column, 3);
        expect(e.message, contains("Expected ',' or '}'"));
      }
    });

    test('rejects excessive nesting instead of overflowing the stack', () {
      final deep = '${'[' * 2000}${']' * 2000}';
      expect(
        () => parseJsonWithPositions(deep),
        throwsA(
          isA<JsonSyntaxException>().having(
            (e) => e.message,
            'message',
            contains('too deep'),
          ),
        ),
      );
    });
  });
}
