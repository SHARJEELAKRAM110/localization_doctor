/// Parser for the ICU message subset understood by Flutter's `gen-l10n`:
///
/// * plain placeholders: `{name}`
/// * plural and select: `{count, plural, =0{none} one{one} other{{count} items}}`
/// * date and time arguments: `{when, date, yMd}`
/// * optional single-quote escaping (`use-escaping: true` in `l10n.yaml`)
/// * optional relaxed syntax (`relax-syntax: true`), where braces that do not
///   start a known placeholder are treated as literal text.
library;

/// How an argument is used in a message.
enum IcuArgumentKind { simple, plural, select, date, time }

class IcuSyntaxError {
  const IcuSyntaxError(this.message, this.offset);

  final String message;

  /// 0-based offset within the message string.
  final int offset;

  @override
  String toString() => '$message (at character ${offset + 1})';
}

class IcuParseResult {
  IcuParseResult(this.arguments, this.errors, this.warnings);

  /// Argument names and how each is used. When an argument appears several
  /// times the first non-simple kind wins.
  final Map<String, IcuArgumentKind> arguments;

  /// Syntax errors. When non-empty, [arguments] may be incomplete.
  final List<IcuSyntaxError> errors;

  /// Non-fatal problems, such as a plural without an `other` case.
  final List<IcuSyntaxError> warnings;

  bool get isValid => errors.isEmpty;
}

/// Parses [message]. When [relaxedPlaceholders] is non-null, relaxed syntax
/// is enabled and only braces followed by one of those names open an
/// argument.
IcuParseResult parseIcuMessage(
  String message, {
  bool useEscaping = false,
  Set<String>? relaxedPlaceholders,
}) {
  final parser = _IcuParser(message, useEscaping, relaxedPlaceholders);
  try {
    parser.parseMessage(nested: false);
  } on _IcuFailure catch (failure) {
    parser.errors.add(IcuSyntaxError(failure.message, failure.offset));
  }
  return IcuParseResult(parser.arguments, parser.errors, parser.warnings);
}

class _IcuFailure implements Exception {
  _IcuFailure(this.message, this.offset);

  final String message;
  final int offset;
}

class _IcuParser {
  _IcuParser(this.source, this.useEscaping, this.relaxedPlaceholders);

  final String source;
  final bool useEscaping;
  final Set<String>? relaxedPlaceholders;

  final arguments = <String, IcuArgumentKind>{};
  final errors = <IcuSyntaxError>[];
  final warnings = <IcuSyntaxError>[];

  int pos = 0;

  static final _identifier = RegExp(r'[a-zA-Z0-9|_]+');
  static final _number = RegExp('[0-9]+');

  bool get atEnd => pos >= source.length;
  String get current => source[pos];

  Never fail(String message, [int? offset]) =>
      throw _IcuFailure(message, offset ?? pos);

  /// Parses literal text and arguments until the end of input or, when
  /// [nested], until the closing brace of a plural/select case.
  void parseMessage({required bool nested}) {
    while (!atEnd) {
      final char = current;
      if (char == "'" && useEscaping) {
        _skipQuoted();
      } else if (char == '{') {
        if (_isRelaxedLiteralBrace()) {
          pos++;
        } else {
          _parseArgument();
        }
      } else if (char == '}') {
        if (nested) return;
        if (relaxedPlaceholders != null) {
          pos++;
        } else {
          fail("Unmatched '}'");
        }
      } else {
        pos++;
      }
    }
    if (nested) fail('Unexpected end of message, expected }');
  }

  bool _isRelaxedLiteralBrace() {
    final known = relaxedPlaceholders;
    if (known == null) return false;
    var i = pos + 1;
    while (i < source.length && source[i].trim().isEmpty) {
      i++;
    }
    final match = _identifier.matchAsPrefix(source, i);
    return match == null || !known.contains(match[0]);
  }

  void _skipQuoted() {
    final start = pos;
    final close = source.indexOf("'", pos + 1);
    if (close == -1) fail('Unmatched single quote', start);
    pos = close + 1;
  }

  void _skipWhitespace() {
    while (!atEnd && current.trim().isEmpty) {
      pos++;
    }
  }

  String _readIdentifier(String expected) {
    _skipWhitespace();
    final match = _identifier.matchAsPrefix(source, pos);
    if (match == null) {
      fail(
        atEnd
            ? 'Unexpected end of message, expected $expected'
            : "Expected $expected but found '$current'",
      );
    }
    pos = match.end;
    return match[0]!;
  }

  void _expect(String char) {
    _skipWhitespace();
    if (atEnd) fail("Unexpected end of message, expected '$char'");
    if (current != char) fail("Expected '$char' but found '$current'");
    pos++;
  }

  void _record(String name, IcuArgumentKind kind) {
    final existing = arguments[name];
    if (existing == null || existing == IcuArgumentKind.simple) {
      arguments[name] = kind;
    }
  }

  void _parseArgument() {
    final open = pos;
    pos++; // {
    final name = _readIdentifier('a placeholder name');
    _skipWhitespace();
    if (atEnd) fail("Unclosed '{'", open);
    if (current == '}') {
      pos++;
      _record(name, IcuArgumentKind.simple);
      return;
    }
    if (current != ',') fail("Expected ',' or '}' after '$name'");
    pos++;
    final type = _readIdentifier('an argument type');
    switch (type) {
      case 'plural':
      case 'select':
        _expect(',');
        _record(
          name,
          type == 'plural' ? IcuArgumentKind.plural : IcuArgumentKind.select,
        );
        _parseCases(type, open);
      case 'date':
      case 'time':
        _expect(',');
        _readIdentifier('a $type format');
        _expect('}');
        _record(
          name,
          type == 'date' ? IcuArgumentKind.date : IcuArgumentKind.time,
        );
      default:
        fail("Unknown argument type '$type' for '$name'");
    }
  }

  void _parseCases(String type, int open) {
    var hasOther = false;
    var caseCount = 0;
    while (true) {
      _skipWhitespace();
      if (atEnd) fail("Unclosed '{'", open);
      if (current == '}') {
        pos++;
        break;
      }
      String selector;
      if (current == '=') {
        pos++;
        final match = _number.matchAsPrefix(source, pos);
        if (match == null) fail("Expected a number after '='");
        pos = match.end;
        selector = '=${match[0]}';
      } else {
        selector = _readIdentifier('a $type case');
      }
      if (selector == 'other') hasOther = true;
      _expect('{');
      parseMessage(nested: true);
      pos++; // closing } of the case
      caseCount++;
    }
    if (caseCount == 0) fail('The $type message has no cases', open);
    if (!hasOther) {
      warnings.add(
        IcuSyntaxError("The $type message has no 'other' case", open),
      );
    }
  }
}

/// Extracts placeholders from a JSON translation value using a user-provided
/// pattern. Group 1 is the placeholder name; when group 1 is empty or absent
/// the match is a positional placeholder (for example `{}`).
class PatternPlaceholders {
  PatternPlaceholders(this.named, this.positionalCount);

  final Set<String> named;
  final int positionalCount;
}

PatternPlaceholders extractPatternPlaceholders(String value, RegExp pattern) {
  final named = <String>{};
  var positional = 0;
  for (final match in pattern.allMatches(value)) {
    // A backslash before the match marks it as an escaped literal.
    if (match.start > 0 && value[match.start - 1] == r'\') continue;
    final name = match.groupCount >= 1 ? match[1] : null;
    if (name == null || name.isEmpty) {
      positional++;
    } else {
      named.add(name);
    }
  }
  return PatternPlaceholders(named, positional);
}
