import 'diagnostic.dart';

/// Translation coverage of one locale within one bundle.
///
/// [total] is the number of non-ignored message keys in the base locale.
/// A key counts as [translated] only when it is present with a non-empty
/// string value. Empty strings and values of the wrong type are counted in
/// [empty] and [invalid] respectively and do not count as translated.
/// ARB `@` metadata entries are never counted.
class LocaleCoverage {
  const LocaleCoverage({
    required this.bundle,
    required this.locale,
    required this.isBase,
    required this.isOptional,
    required this.total,
    required this.translated,
    required this.missing,
    required this.empty,
    required this.invalid,
    this.fileValid = true,
  });

  final String bundle;
  final String locale;
  final bool isBase;
  final bool isOptional;
  final int total;
  final int translated;
  final int missing;
  final int empty;
  final int invalid;

  /// False when the locale file could not be parsed; all keys then count as
  /// missing.
  final bool fileValid;

  /// Percentage of translated keys, rounded to one decimal place.
  /// A bundle with no keys has 100% coverage.
  double get percent =>
      total == 0 ? 100 : (translated * 1000 / total).roundToDouble() / 10;

  Map<String, Object?> toJson() => {
    'bundle': bundle,
    'locale': locale,
    'isBase': isBase,
    'isOptional': isOptional,
    'total': total,
    'translated': translated,
    'missing': missing,
    'empty': empty,
    'invalid': invalid,
    'fileValid': fileValid,
    'coverage': percent,
  };
}

/// Summary of a bundle discovered during the audit.
class BundleSummary {
  const BundleSummary({
    required this.id,
    required this.format,
    required this.baseLocale,
    required this.locales,
    required this.files,
  });

  final String id;
  final String format;
  final String? baseLocale;
  final List<String> locales;
  final List<String> files;

  Map<String, Object?> toJson() => {
    'id': id,
    'format': format,
    'baseLocale': baseLocale,
    'locales': locales,
    'files': files,
  };
}

/// Complete, renderer-independent result of an audit.
class AuditResult {
  AuditResult({
    required this.toolVersion,
    required this.projectPath,
    required this.generatedAt,
    required List<Diagnostic> diagnostics,
    required this.coverage,
    required this.bundles,
    required this.failOn,
    this.suppressedCount = 0,
    this.skippedFiles = const [],
    this.scannedSourceFiles = 0,
  }) : diagnostics = List.unmodifiable(diagnostics.toList()..sort());

  final String toolVersion;

  /// Absolute project path with forward slashes.
  final String projectPath;

  /// Time the audit finished (UTC). The only non-deterministic field.
  final DateTime generatedAt;

  /// Diagnostics in deterministic order.
  final List<Diagnostic> diagnostics;
  final List<LocaleCoverage> coverage;
  final List<BundleSummary> bundles;

  /// Lowest severity that makes the audit fail.
  final Severity failOn;

  /// Number of diagnostics hidden by ignore rules.
  final int suppressedCount;

  /// Files in localization directories that were not recognized as
  /// translation files, with the reason.
  final List<String> skippedFiles;

  /// Number of Dart files scanned for key usage.
  final int scannedSourceFiles;

  int count(Severity severity) =>
      diagnostics.where((d) => d.severity == severity).length;

  /// Diagnostics that violate the configured policy.
  List<Diagnostic> get violations => [
    for (final d in diagnostics)
      if (d.severity.index >= failOn.index) d,
  ];

  bool get passed => violations.isEmpty;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'tool': {'name': 'localization_doctor', 'version': toolVersion},
    'projectPath': projectPath,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'status': passed ? 'passed' : 'failed',
    'failOn': failOn.name,
    'summary': {
      'errors': count(Severity.error),
      'warnings': count(Severity.warning),
      'infos': count(Severity.info),
      'violations': violations.length,
      'suppressed': suppressedCount,
      'scannedSourceFiles': scannedSourceFiles,
    },
    'bundles': [for (final b in bundles) b.toJson()],
    'coverage': [for (final c in coverage) c.toJson()],
    'diagnostics': [for (final d in diagnostics) d.toJson()],
    'skippedFiles': skippedFiles,
  };
}
