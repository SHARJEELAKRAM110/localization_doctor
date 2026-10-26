/// Severity of a diagnostic. Ordered from least to most severe.
enum Severity {
  info,
  warning,
  error;

  /// Parses a severity name, returning `null` when [value] is unknown.
  static Severity? tryParse(String value) {
    for (final severity in Severity.values) {
      if (severity.name == value) return severity;
    }
    return null;
  }
}

/// How certain the tool is that a diagnostic describes a real problem.
enum Confidence {
  /// Directly observed in the parsed input.
  definite,

  /// Likely, but static analysis cannot rule out other explanations.
  probable,

  /// Static analysis found evidence both ways; review manually.
  inconclusive,
}

/// Stable diagnostic codes. Codes are never renumbered or reused.
enum DiagnosticCode {
  missingKey('LOC001', 'Missing translation key'),
  unusedKey('LOC002', 'Unused translation key'),
  duplicateKey('LOC003', 'Duplicate translation key'),
  placeholderMismatch('LOC004', 'Placeholder mismatch'),
  emptyValue('LOC005', 'Empty translation value'),
  invalidFile('LOC006', 'Invalid translation file'),
  configuration('LOC007', 'Localization configuration issue'),
  extraKey('LOC008', 'Key not present in base locale'),
  invalidValueType('LOC009', 'Invalid translation value type'),
  messageSyntax('LOC010', 'ICU message syntax error'),
  structureMismatch('LOC011', 'Inconsistent key structure'),
  emptyLocaleFile('LOC012', 'Locale file contains no translations'),
  missingLocale('LOC013', 'Missing locale file'),
  arbMetadata('LOC014', 'ARB metadata issue'),
  dynamicKeyUsage('LOC015', 'Dynamic key usage limits unused-key analysis'),
  undefinedKey('LOC016', 'Key referenced in source but not defined');

  const DiagnosticCode(this.id, this.title);

  /// Stable identifier such as `LOC001`.
  final String id;

  /// Short human-readable title.
  final String title;

  /// Codes that can never be suppressed through ignore rules, because hiding
  /// them would hide data loss or an unreadable project.
  bool get isSuppressible => this != invalidFile;

  /// Looks up a code by its [id], returning `null` when unknown.
  static DiagnosticCode? tryParse(String id) {
    for (final code in DiagnosticCode.values) {
      if (code.id == id) return code;
    }
    return null;
  }
}

/// A position inside a project file. Paths are relative to the project root
/// and always use forward slashes so reports are identical on every platform.
class SourceLocation implements Comparable<SourceLocation> {
  const SourceLocation(this.path, {this.line, this.column});

  final String path;

  /// 1-based line, when known.
  final int? line;

  /// 1-based column, when known.
  final int? column;

  @override
  String toString() {
    if (line == null) return path;
    if (column == null) return '$path:$line';
    return '$path:$line:$column';
  }

  Map<String, Object?> toJson() => {
    'path': path,
    'line': line,
    'column': column,
  };

  @override
  int compareTo(SourceLocation other) {
    final byPath = path.compareTo(other.path);
    if (byPath != 0) return byPath;
    final byLine = (line ?? 0).compareTo(other.line ?? 0);
    if (byLine != 0) return byLine;
    return (column ?? 0).compareTo(other.column ?? 0);
  }

  @override
  bool operator ==(Object other) =>
      other is SourceLocation &&
      other.path == path &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode => Object.hash(path, line, column);
}

/// A single audit finding. Diagnostics are plain data; reporters decide how to
/// render them.
class Diagnostic implements Comparable<Diagnostic> {
  const Diagnostic({
    required this.code,
    required this.severity,
    required this.message,
    this.confidence = Confidence.definite,
    this.location,
    this.relatedLocations = const [],
    this.key,
    this.locale,
    this.bundle,
    this.suggestion,
  });

  final DiagnosticCode code;
  final Severity severity;
  final Confidence confidence;
  final String message;
  final SourceLocation? location;

  /// Extra locations, for example the first occurrence of a duplicate key.
  final List<SourceLocation> relatedLocations;

  /// Canonical translation key the diagnostic is about, if any.
  final String? key;

  /// Locale the diagnostic is about, if any.
  final String? locale;

  /// Identifier of the translation bundle, e.g. `lib/l10n/app_*.arb`.
  final String? bundle;

  /// Recommended action.
  final String? suggestion;

  Diagnostic copyWith({Severity? severity, Confidence? confidence}) =>
      Diagnostic(
        code: code,
        severity: severity ?? this.severity,
        confidence: confidence ?? this.confidence,
        message: message,
        location: location,
        relatedLocations: relatedLocations,
        key: key,
        locale: locale,
        bundle: bundle,
        suggestion: suggestion,
      );

  Map<String, Object?> toJson() => {
    'code': code.id,
    'title': code.title,
    'severity': severity.name,
    'confidence': confidence.name,
    'message': message,
    'bundle': bundle,
    'locale': locale,
    'key': key,
    'location': location?.toJson(),
    'relatedLocations': [for (final l in relatedLocations) l.toJson()],
    'suggestion': suggestion,
  };

  /// Deterministic ordering: most severe first, then code, location, key.
  @override
  int compareTo(Diagnostic other) {
    final bySeverity = other.severity.index.compareTo(severity.index);
    if (bySeverity != 0) return bySeverity;
    final byCode = code.id.compareTo(other.code.id);
    if (byCode != 0) return byCode;
    final byBundle = (bundle ?? '').compareTo(other.bundle ?? '');
    if (byBundle != 0) return byBundle;
    final a = location;
    final b = other.location;
    if (a != null && b != null) {
      final byLocation = a.compareTo(b);
      if (byLocation != 0) return byLocation;
    } else if (a != null || b != null) {
      return a == null ? -1 : 1;
    }
    final byLocale = (locale ?? '').compareTo(other.locale ?? '');
    if (byLocale != 0) return byLocale;
    final byKey = (key ?? '').compareTo(other.key ?? '');
    if (byKey != 0) return byKey;
    return message.compareTo(other.message);
  }

  @override
  String toString() =>
      '${severity.name} ${code.id} ${location ?? ''} $message'.trim();
}
