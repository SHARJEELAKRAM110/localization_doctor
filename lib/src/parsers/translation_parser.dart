import '../models/diagnostic.dart';
import '../models/translation.dart';
import 'json_source_parser.dart';

/// Result of parsing one translation file: the file model plus any
/// diagnostics discovered while reading it (duplicates, invalid types, ...).
class ParsedTranslationFile {
  ParsedTranslationFile(this.file, this.diagnostics);

  final TranslationFile file;
  final List<Diagnostic> diagnostics;
}

SourceLocation _loc(String path, JsonPosition p) =>
    SourceLocation(path, line: p.line, column: p.column);

/// Reports duplicate keys inside a single JSON object. The last occurrence
/// wins, matching `jsonDecode` and Flutter's `gen-l10n`.
List<Diagnostic> _duplicateDiagnostics(
  JsonObject object,
  String path, {
  required String bundle,
  required String locale,
  String keyPrefix = '',
  String context = '',
}) {
  final firstSeen = <String, JsonMember>{};
  final diagnostics = <Diagnostic>[];
  for (final member in object.members) {
    final previous = firstSeen[member.key];
    if (previous == null) {
      firstSeen[member.key] = member;
      continue;
    }
    final displayKey = '$keyPrefix${member.key}';
    diagnostics.add(
      Diagnostic(
        code: DiagnosticCode.duplicateKey,
        severity: Severity.error,
        message:
            'Duplicate key "$displayKey"$context. JSON parsers keep only the '
            'last value, so the value at ${previous.keyPosition} is silently '
            'discarded.',
        location: _loc(path, member.keyPosition),
        relatedLocations: [_loc(path, previous.keyPosition)],
        key: displayKey,
        locale: locale,
        bundle: bundle,
        suggestion: 'Remove or rename one of the "$displayKey" entries.',
      ),
    );
  }
  return diagnostics;
}

/// Returns the last member for each key, preserving first-seen order.
Map<String, JsonMember> _lastWins(JsonObject object) {
  final result = <String, JsonMember>{};
  for (final member in object.members) {
    result.remove(member.key);
    result[member.key] = member;
  }
  return result;
}

ParsedTranslationFile _invalidFile({
  required String path,
  required TranslationFormat format,
  required String locale,
  required String bundle,
  required String message,
  JsonPosition? position,
}) {
  final diagnostic = Diagnostic(
    code: DiagnosticCode.invalidFile,
    severity: Severity.error,
    message: message,
    location: position == null ? SourceLocation(path) : _loc(path, position),
    locale: locale,
    bundle: bundle,
    suggestion: 'Fix the file so it is valid JSON with an object at the root.',
  );
  return ParsedTranslationFile(
    TranslationFile(
      path: path,
      format: format,
      locale: locale,
      entries: const {},
      parseError: diagnostic,
    ),
    [diagnostic],
  );
}

JsonObject? _parseRoot(
  String content,
  String path,
  TranslationFormat format,
  String locale,
  String bundle,
  void Function(ParsedTranslationFile) onError,
) {
  final JsonNode root;
  try {
    root = parseJsonWithPositions(content);
  } on JsonSyntaxException catch (e) {
    onError(
      _invalidFile(
        path: path,
        format: format,
        locale: locale,
        bundle: bundle,
        message: 'Malformed JSON: ${e.message}.',
        position: e.position,
      ),
    );
    return null;
  }
  if (root is! JsonObject) {
    onError(
      _invalidFile(
        path: path,
        format: format,
        locale: locale,
        bundle: bundle,
        message:
            'Expected a JSON object at the root but found ${root.typeName}.',
        position: root.position,
      ),
    );
    return null;
  }
  return root;
}

/// Parses an ARB file.
///
/// * Keys starting with `@@` are global attributes (`@@locale`, ...).
/// * Keys starting with `@` hold metadata for the message with the same name.
/// * Every other key must hold a string message.
ParsedTranslationFile parseArbFile({
  required String content,
  required String path,
  required String locale,
  required String bundle,
}) {
  ParsedTranslationFile? failure;
  final root = _parseRoot(
    content,
    path,
    TranslationFormat.arb,
    locale,
    bundle,
    (f) => failure = f,
  );
  if (root == null) return failure!;

  final diagnostics = _duplicateDiagnostics(
    root,
    path,
    bundle: bundle,
    locale: locale,
  );
  final entries = <String, TranslationEntry>{};
  final metadata = <String, ArbMetadata>{};
  String? declaredLocale;

  for (final member in _lastWins(root).values) {
    final key = member.key;
    final location = _loc(path, member.keyPosition);
    final value = member.value;
    if (key.startsWith('@@')) {
      if (key == '@@locale') {
        if (value is JsonString) {
          declaredLocale = value.value;
        } else {
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.arbMetadata,
              severity: Severity.warning,
              message: '"@@locale" must be a string, found ${value.typeName}.',
              location: location,
              locale: locale,
              bundle: bundle,
            ),
          );
        }
      }
      continue;
    }
    if (key.startsWith('@')) {
      final messageKey = key.substring(1);
      if (value is! JsonObject) {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCode.arbMetadata,
            severity: Severity.warning,
            message:
                'Metadata "$key" must be an object, found ${value.typeName}.',
            location: location,
            key: messageKey,
            locale: locale,
            bundle: bundle,
            suggestion: 'Use an object such as {"description": "..."}.',
          ),
        );
        continue;
      }
      diagnostics.addAll(
        _duplicateDiagnostics(
          value,
          path,
          bundle: bundle,
          locale: locale,
          keyPrefix: '$key.',
        ),
      );
      metadata[messageKey] = _parseArbMetadata(
        messageKey,
        value,
        location,
        path,
        bundle,
        locale,
        diagnostics,
      );
      continue;
    }
    if (value is JsonString) {
      entries[key] = TranslationEntry(
        key: key,
        kind: EntryKind.message,
        value: value.value,
        location: location,
      );
    } else {
      entries[key] = TranslationEntry(
        key: key,
        kind: EntryKind.invalid,
        valueType: value.typeName,
        location: location,
      );
      diagnostics.add(
        Diagnostic(
          code: DiagnosticCode.invalidValueType,
          severity: Severity.error,
          message:
              'ARB message "$key" must be a string, found ${value.typeName}.',
          location: location,
          key: key,
          locale: locale,
          bundle: bundle,
          suggestion:
              'Store the message as a string. Plurals and selects use '
              'ICU syntax inside the string.',
        ),
      );
    }
  }

  return ParsedTranslationFile(
    TranslationFile(
      path: path,
      format: TranslationFormat.arb,
      locale: locale,
      entries: entries,
      metadata: metadata,
      declaredLocale: declaredLocale,
    ),
    diagnostics,
  );
}

ArbMetadata _parseArbMetadata(
  String messageKey,
  JsonObject object,
  SourceLocation location,
  String path,
  String bundle,
  String locale,
  List<Diagnostic> diagnostics,
) {
  final placeholdersMember = _lastWins(object)['placeholders'];
  if (placeholdersMember == null) {
    return ArbMetadata(key: messageKey, location: location);
  }
  final node = placeholdersMember.value;
  if (node is! JsonObject) {
    diagnostics.add(
      Diagnostic(
        code: DiagnosticCode.arbMetadata,
        severity: Severity.warning,
        message:
            '"@$messageKey.placeholders" must be an object, found '
            '${node.typeName}.',
        location: _loc(path, placeholdersMember.keyPosition),
        key: messageKey,
        locale: locale,
        bundle: bundle,
      ),
    );
    return ArbMetadata(key: messageKey, location: location);
  }
  diagnostics.addAll(
    _duplicateDiagnostics(
      node,
      path,
      bundle: bundle,
      locale: locale,
      keyPrefix: '@$messageKey.placeholders.',
    ),
  );
  final placeholders = <String, PlaceholderMetadata>{};
  for (final member in _lastWins(node).values) {
    String? type;
    String? format;
    final definition = member.value;
    if (definition is JsonObject) {
      final fields = _lastWins(definition);
      final typeNode = fields['type']?.value;
      final formatNode = fields['format']?.value;
      if (typeNode is JsonString) type = typeNode.value;
      if (formatNode is JsonString) format = formatNode.value;
    } else {
      diagnostics.add(
        Diagnostic(
          code: DiagnosticCode.arbMetadata,
          severity: Severity.warning,
          message:
              'Placeholder "${member.key}" of "$messageKey" must be an '
              'object, found ${definition.typeName}.',
          location: _loc(path, member.keyPosition),
          key: messageKey,
          locale: locale,
          bundle: bundle,
        ),
      );
    }
    placeholders[member.key] = PlaceholderMetadata(
      member.key,
      type: type,
      format: format,
    );
  }
  return ArbMetadata(
    key: messageKey,
    location: location,
    placeholders: placeholders,
  );
}

/// Parses a JSON translation file. Nested objects are flattened into
/// canonical keys joined with [separator] (e.g. `home.title`).
///
/// A flat key that contains the separator and collides with a nested path
/// (for example `"home.title"` next to `"home": {"title": ...}`) is reported
/// as ambiguous instead of being silently merged.
ParsedTranslationFile parseJsonTranslationFile({
  required String content,
  required String path,
  required String locale,
  required String bundle,
  String separator = '.',
}) {
  ParsedTranslationFile? failure;
  final root = _parseRoot(
    content,
    path,
    TranslationFormat.json,
    locale,
    bundle,
    (f) => failure = f,
  );
  if (root == null) return failure!;

  final diagnostics = <Diagnostic>[];
  final entries = <String, TranslationEntry>{};
  final objectPaths = <String, SourceLocation>{};

  void visit(JsonObject object, String prefix) {
    diagnostics.addAll(
      _duplicateDiagnostics(
        object,
        path,
        bundle: bundle,
        locale: locale,
        keyPrefix: prefix,
        context: prefix.isEmpty
            ? ''
            : ' in object "${prefix.substring(0, prefix.length - separator.length)}"',
      ),
    );
    for (final member in _lastWins(object).values) {
      final key = '$prefix${member.key}';
      final location = _loc(path, member.keyPosition);
      final value = member.value;
      final clash = entries[key]?.location ?? objectPaths[key];
      if (clash != null) {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCode.structureMismatch,
            severity: Severity.error,
            message:
                'Key "$key" is ambiguous: it is defined both as a flat key '
                'containing "$separator" and through nested objects.',
            location: location,
            relatedLocations: [clash],
            key: key,
            locale: locale,
            bundle: bundle,
            suggestion:
                'Use either nested objects or flat dotted keys for '
                '"$key", not both.',
          ),
        );
        continue;
      }
      if (value is JsonObject) {
        objectPaths[key] = location;
        visit(value, '$key$separator');
      } else if (value is JsonString) {
        entries[key] = TranslationEntry(
          key: key,
          kind: EntryKind.message,
          value: value.value,
          location: location,
        );
      } else {
        entries[key] = TranslationEntry(
          key: key,
          kind: EntryKind.invalid,
          valueType: value.typeName,
          location: location,
        );
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCode.invalidValueType,
            severity: Severity.error,
            message:
                'Translation "$key" must be a string or an object, found '
                '${value.typeName}.',
            location: location,
            key: key,
            locale: locale,
            bundle: bundle,
            suggestion: 'Replace the value with a string.',
          ),
        );
      }
    }
  }

  visit(root, '');
  return ParsedTranslationFile(
    TranslationFile(
      path: path,
      format: TranslationFormat.json,
      locale: locale,
      entries: entries,
      objectPaths: objectPaths,
    ),
    diagnostics,
  );
}
