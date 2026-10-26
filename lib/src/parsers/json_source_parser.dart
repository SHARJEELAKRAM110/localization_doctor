/// A small, strict JSON (RFC 8259) parser that keeps source positions and
/// preserves every object member, including duplicate keys.
///
/// `dart:convert`'s `jsonDecode` silently keeps only the last value of a
/// duplicated key, which makes duplicate detection impossible after decoding.
/// This parser records members in order so callers can detect duplicates.
library;

/// 1-based position in a source text.
class JsonPosition {
  const JsonPosition(this.offset, this.line, this.column);

  final int offset;
  final int line;
  final int column;

  @override
  String toString() => '$line:$column';
}

/// Thrown when the input is not valid JSON.
class JsonSyntaxException implements Exception {
  JsonSyntaxException(this.message, this.position);

  final String message;
  final JsonPosition position;

  @override
  String toString() => 'JsonSyntaxException: $message at $position';
}

sealed class JsonNode {
  const JsonNode(this.position);

  /// Position of the first character of the value.
  final JsonPosition position;

  /// Human-readable JSON type name.
  String get typeName;
}

class JsonMember {
  const JsonMember(this.key, this.keyPosition, this.value);

  final String key;
  final JsonPosition keyPosition;
  final JsonNode value;
}

class JsonObject extends JsonNode {
  const JsonObject(super.position, this.members);

  /// Members in source order. May contain the same key more than once.
  final List<JsonMember> members;

  @override
  String get typeName => 'object';
}

class JsonArray extends JsonNode {
  const JsonArray(super.position, this.elements);

  final List<JsonNode> elements;

  @override
  String get typeName => 'array';
}

class JsonString extends JsonNode {
  const JsonString(super.position, this.value);

  final String value;

  @override
  String get typeName => 'string';
}

class JsonNumber extends JsonNode {
  const JsonNumber(super.position, this.value);

  final num value;

  @override
  String get typeName => 'number';
}

class JsonBool extends JsonNode {
  const JsonBool(super.position, this.value);

  final bool value;

  @override
  String get typeName => 'boolean';
}

class JsonNull extends JsonNode {
  const JsonNull(super.position);

  @override
  String get typeName => 'null';
}

/// Parses [source] into a [JsonNode] tree. A leading byte order mark is
/// ignored. Throws [JsonSyntaxException] on invalid input.
JsonNode parseJsonWithPositions(String source) =>
    _JsonParser(source).parseDocument();

class _JsonParser {
  _JsonParser(this._source);

  final String _source;
  int _offset = 0;
  int _line = 1;
  int _column = 1;

  static const _maxDepth = 512;
  int _depth = 0;

  JsonPosition get _position => JsonPosition(_offset, _line, _column);

  bool get _atEnd => _offset >= _source.length;

  int get _current => _source.codeUnitAt(_offset);

  JsonNode parseDocument() {
    if (!_atEnd && _current == 0xFEFF) _offset++;
    _skipWhitespace();
    if (_atEnd) _fail('Expected a JSON value but the file is empty');
    final value = _parseValue();
    _skipWhitespace();
    if (!_atEnd) {
      _fail('Unexpected ${_describeCurrent()} after the end of the JSON value');
    }
    return value;
  }

  Never _fail(String message, [JsonPosition? position]) =>
      throw JsonSyntaxException(message, position ?? _position);

  String _describeCurrent() {
    if (_atEnd) return 'end of file';
    final char = _source[_offset];
    if (char == '\n') return 'line break';
    return "character '$char'";
  }

  void _advance() {
    if (_current == 0x0A) {
      _line++;
      _column = 1;
    } else {
      _column++;
    }
    _offset++;
  }

  void _skipWhitespace() {
    while (!_atEnd) {
      final c = _current;
      if (c == 0x20 || c == 0x09 || c == 0x0A) {
        _advance();
      } else if (c == 0x0D) {
        // Treat CRLF as a single line break; the LF advances the line.
        _offset++;
      } else if (c == 0x2F) {
        _fail('Comments are not allowed in JSON');
      } else {
        return;
      }
    }
  }

  void _expect(int char, String description) {
    if (_atEnd || _current != char) {
      _fail('Expected $description but found ${_describeCurrent()}');
    }
    _advance();
  }

  JsonNode _parseValue() {
    if (_atEnd) _fail('Unexpected end of file, expected a value');
    final c = _current;
    switch (c) {
      case 0x7B: // {
        return _parseObject();
      case 0x5B: // [
        return _parseArray();
      case 0x22: // "
        final position = _position;
        return JsonString(position, _parseString());
      case 0x74: // t
        return _parseLiteral('true', JsonBool(_position, true));
      case 0x66: // f
        return _parseLiteral('false', JsonBool(_position, false));
      case 0x6E: // n
        return _parseLiteral('null', JsonNull(_position));
      default:
        if (c == 0x2D || (c >= 0x30 && c <= 0x39)) return _parseNumber();
        if (c == 0x27) _fail('Strings must use double quotes');
        _fail('Unexpected ${_describeCurrent()}, expected a value');
    }
  }

  JsonNode _parseLiteral(String literal, JsonNode node) {
    if (!_source.startsWith(literal, _offset)) {
      _fail('Unexpected ${_describeCurrent()}, expected a value');
    }
    for (var i = 0; i < literal.length; i++) {
      _advance();
    }
    return node;
  }

  void _enter() {
    if (++_depth > _maxDepth) _fail('JSON nesting is too deep');
  }

  JsonObject _parseObject() {
    final position = _position;
    _enter();
    _advance(); // {
    final members = <JsonMember>[];
    _skipWhitespace();
    if (!_atEnd && _current == 0x7D) {
      _advance();
      _depth--;
      return JsonObject(position, members);
    }
    while (true) {
      _skipWhitespace();
      if (_atEnd) _fail('Unterminated object starting at $position');
      if (_current == 0x7D) _fail('Trailing commas are not allowed in JSON');
      if (_current != 0x22) {
        _fail(
          'Expected a double-quoted property name but found '
          '${_describeCurrent()}',
        );
      }
      final keyPosition = _position;
      final key = _parseString();
      _skipWhitespace();
      _expect(0x3A, "':' after property name");
      _skipWhitespace();
      final value = _parseValue();
      members.add(JsonMember(key, keyPosition, value));
      _skipWhitespace();
      if (_atEnd) _fail('Unterminated object starting at $position');
      if (_current == 0x2C) {
        _advance();
        continue;
      }
      if (_current == 0x7D) {
        _advance();
        _depth--;
        return JsonObject(position, members);
      }
      _fail("Expected ',' or '}' but found ${_describeCurrent()}");
    }
  }

  JsonArray _parseArray() {
    final position = _position;
    _enter();
    _advance(); // [
    final elements = <JsonNode>[];
    _skipWhitespace();
    if (!_atEnd && _current == 0x5D) {
      _advance();
      _depth--;
      return JsonArray(position, elements);
    }
    while (true) {
      _skipWhitespace();
      if (!_atEnd && _current == 0x5D) {
        _fail('Trailing commas are not allowed in JSON');
      }
      elements.add(_parseValue());
      _skipWhitespace();
      if (_atEnd) _fail('Unterminated array starting at $position');
      if (_current == 0x2C) {
        _advance();
        continue;
      }
      if (_current == 0x5D) {
        _advance();
        _depth--;
        return JsonArray(position, elements);
      }
      _fail("Expected ',' or ']' but found ${_describeCurrent()}");
    }
  }

  String _parseString() {
    final start = _position;
    _advance(); // opening quote
    final buffer = StringBuffer();
    while (true) {
      if (_atEnd) _fail('Unterminated string', start);
      final c = _current;
      if (c == 0x22) {
        _advance();
        return buffer.toString();
      }
      if (c == 0x5C) {
        _advance();
        if (_atEnd) _fail('Unterminated string', start);
        final escape = _current;
        switch (escape) {
          case 0x22:
            buffer.write('"');
          case 0x5C:
            buffer.write(r'\');
          case 0x2F:
            buffer.write('/');
          case 0x62:
            buffer.write('\b');
          case 0x66:
            buffer.write('\f');
          case 0x6E:
            buffer.write('\n');
          case 0x72:
            buffer.write('\r');
          case 0x74:
            buffer.write('\t');
          case 0x75:
            _advance();
            buffer.writeCharCode(_parseHex4());
            continue;
          default:
            _fail('Invalid escape sequence \\${String.fromCharCode(escape)}');
        }
        _advance();
        continue;
      }
      if (c < 0x20) {
        _fail('Control characters must be escaped inside strings');
      }
      buffer.writeCharCode(c);
      _advance();
    }
  }

  int _parseHex4() {
    if (_offset + 4 > _source.length) _fail('Invalid \\u escape sequence');
    final hex = _source.substring(_offset, _offset + 4);
    final value = int.tryParse(hex, radix: 16);
    if (value == null || hex.contains(RegExp('[^0-9a-fA-F]'))) {
      _fail('Invalid \\u escape sequence');
    }
    for (var i = 0; i < 4; i++) {
      _advance();
    }
    return value;
  }

  static final _numberPattern = RegExp(
    r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
  );

  JsonNumber _parseNumber() {
    final position = _position;
    final match = _numberPattern.matchAsPrefix(_source, _offset);
    if (match == null) _fail('Invalid number');
    final text = match[0]!;
    for (var i = 0; i < text.length; i++) {
      _advance();
    }
    if (!_atEnd) {
      final c = _current;
      if ((c >= 0x30 && c <= 0x39) || c == 0x2E) {
        _fail('Invalid number', position);
      }
    }
    return JsonNumber(position, num.parse(text));
  }
}
