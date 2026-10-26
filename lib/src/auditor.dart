import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import 'analyzers/audit_context.dart';
import 'analyzers/configuration_analyzer.dart';
import 'analyzers/missing_key_analyzer.dart';
import 'analyzers/placeholder_analyzer.dart';
import 'analyzers/unused_key_analyzer.dart';
import 'config/config.dart';
import 'discovery/locale_discovery.dart';
import 'discovery/locale_name.dart';
import 'flutter/project_info.dart';
import 'models/audit_result.dart';
import 'models/diagnostic.dart';
import 'models/translation.dart';
import 'parsers/translation_parser.dart';
import 'source/usage_scanner.dart';
import 'version.dart';

/// Thrown when the audit cannot run at all (for example, the project path
/// does not exist). Maps to exit code 3.
class AuditException implements Exception {
  AuditException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Runs a localization audit on a project directory.
///
/// ```dart
/// final result = LocalizationAuditor(
///   projectPath: '.',
///   config: loadConfig('.'),
/// ).run();
/// print(result.passed);
/// ```
class LocalizationAuditor {
  LocalizationAuditor({
    required String projectPath,
    this.config = const DoctorConfig(),
    DateTime Function()? clock,
  }) : root = p.normalize(p.absolute(projectPath)),
       _clock = clock ?? DateTime.now;

  /// Absolute, normalized project root.
  final String root;
  final DoctorConfig config;
  final DateTime Function() _clock;

  AuditResult run() {
    if (!Directory(root).existsSync()) {
      throw AuditException('Project directory "$root" does not exist.');
    }
    final project = ProjectInfo.read(root);
    final discovery = discoverTranslationFiles(root, config, project);
    final diagnostics = <Diagnostic>[...discovery.diagnostics];
    final skipped = [...discovery.skipped];

    final bundles = _buildBundles(discovery, diagnostics, skipped);
    for (final bundle in bundles) {
      _selectBaseLocale(bundle, project, diagnostics);
    }

    final context = AuditContext(
      root: root,
      config: config,
      project: project,
      bundles: bundles,
    );

    UsageScanResult? scan;
    if (config.checks.unusedKeys || config.checks.configuration) {
      final l10nOutput = project.l10n.effectiveOutputDir;
      scan = scanSourceUsage(
        root,
        UsageScanOptions(
          sourceDirectories: config.sourceDirectories,
          exclude: [
            ...config.sourceExclude,
            '$l10nOutput/${p.basenameWithoutExtension(project.l10n.outputLocalizationFile)}*.dart',
          ],
          localizationClasses: context.localizationClasses,
          accessors: config.accessors,
          jsonLookupFunctions: config.jsonLookupFunctions,
          keyClasses: config.keyClasses,
          reportMissingDirectories: config.explicitSourceDirectories,
        ),
      );
      diagnostics.addAll(scan.diagnostics);
    }

    final missing = MissingKeyAnalyzer(context);
    final placeholders = PlaceholderAnalyzer(context);
    for (final bundle in bundles) {
      diagnostics
        ..addAll(missing.analyze(bundle))
        ..addAll(placeholders.analyze(bundle));
    }
    if (config.checks.unusedKeys && scan != null && bundles.isNotEmpty) {
      diagnostics.addAll(UnusedKeyAnalyzer(context, scan).analyze());
    }
    if (config.checks.configuration) {
      diagnostics.addAll(
        ConfigurationAnalyzer(context, scan, discovery.directories).analyze(),
      );
    }

    var suppressed = 0;
    final kept = <Diagnostic>[];
    final seen = <String>{};
    for (final diagnostic in diagnostics) {
      if (!config.checks.isEnabled(diagnostic.code)) continue;
      if (_isSuppressed(diagnostic, context)) {
        suppressed++;
        continue;
      }
      final adjusted = _applyPolicy(diagnostic);
      final identity =
          '${adjusted.code.id}|${adjusted.location}|'
          '${adjusted.key}|${adjusted.locale}|${adjusted.message}';
      if (seen.add(identity)) kept.add(adjusted);
    }

    final coverage = missing.coverage
      ..sort((a, b) {
        final byBundle = a.bundle.compareTo(b.bundle);
        if (byBundle != 0) return byBundle;
        if (a.isBase != b.isBase) return a.isBase ? -1 : 1;
        return a.locale.compareTo(b.locale);
      });

    return AuditResult(
      toolVersion: packageVersion,
      projectPath: root.replaceAll(r'\', '/'),
      generatedAt: _clock().toUtc(),
      diagnostics: kept,
      coverage: coverage,
      bundles: [
        for (final b in bundles)
          BundleSummary(
            id: b.id,
            format: b.format.name,
            baseLocale: b.baseLocale,
            locales: b.files.keys.toList()..sort(),
            files: [for (final f in b.files.values) f.path]..sort(),
          ),
      ],
      failOn: config.failOn,
      suppressedCount: suppressed,
      skippedFiles: skipped..sort(),
      scannedSourceFiles: scan?.scannedFiles.length ?? 0,
    );
  }

  List<TranslationBundle> _buildBundles(
    DiscoveryResult discovery,
    List<Diagnostic> diagnostics,
    List<String> skipped,
  ) {
    final bundles = <String, TranslationBundle>{};
    for (final found in discovery.files) {
      final String content;
      try {
        content = File(found.absolutePath).readAsStringSync();
      } on FileSystemException catch (e) {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCode.invalidFile,
            severity: Severity.error,
            message: 'Cannot read file: ${e.osError?.message ?? e.message}.',
            location: SourceLocation(found.path),
            bundle: found.bundleId,
            suggestion: 'Check the file permissions.',
          ),
        );
        continue;
      } on FormatException {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCode.invalidFile,
            severity: Severity.error,
            message: 'File is not valid UTF-8.',
            location: SourceLocation(found.path),
            bundle: found.bundleId,
            suggestion: 'Save the file with UTF-8 encoding.',
          ),
        );
        continue;
      }

      final provisionalLocale = found.locale ?? 'und';
      final parsed = found.format == TranslationFormat.arb
          ? parseArbFile(
              content: content,
              path: found.path,
              locale: provisionalLocale,
              bundle: found.bundleId,
            )
          : parseJsonTranslationFile(
              content: content,
              path: found.path,
              locale: provisionalLocale,
              bundle: found.bundleId,
              separator: config.keySeparator,
            );

      var file = parsed.file;
      var fileDiagnostics = parsed.diagnostics;
      if (found.locale == null) {
        final declared = file.declaredLocale == null
            ? null
            : normalizeLocale(file.declaredLocale!);
        if (declared == null) {
          if (!file.isValid) {
            diagnostics.addAll(fileDiagnostics);
          }
          skipped.add(
            '${found.path} (no locale in file name or "@@locale"; add it to '
            'localization.locale_mappings)',
          );
          continue;
        }
        // Re-parse with the real locale so diagnostics carry it.
        final reparsed = parseArbFile(
          content: content,
          path: found.path,
          locale: declared,
          bundle: found.bundleId,
        );
        file = reparsed.file;
        fileDiagnostics = reparsed.diagnostics;
      }
      diagnostics.addAll(fileDiagnostics);

      final bundle = bundles.putIfAbsent(
        found.bundleId,
        () => TranslationBundle(
          id: found.bundleId,
          directory: found.directory,
          format: found.format,
          files: {},
        ),
      );
      final existing = bundle.files[file.locale];
      if (existing != null) {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCode.configuration,
            severity: Severity.warning,
            message:
                'Both ${existing.path} and ${file.path} provide locale '
                '"${file.locale}" in ${bundle.id}; only ${existing.path} is '
                'audited.',
            location: SourceLocation(file.path),
            locale: file.locale,
            bundle: bundle.id,
            suggestion: 'Keep a single file per locale.',
          ),
        );
        continue;
      }
      bundle.files[file.locale] = file;
    }
    final list = bundles.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    for (final bundle in list) {
      final sorted = bundle.files.keys.toList()..sort();
      final files = {for (final l in sorted) l: bundle.files[l]!};
      bundle.files
        ..clear()
        ..addAll(files);
    }
    return list;
  }

  void _selectBaseLocale(
    TranslationBundle bundle,
    ProjectInfo project,
    List<Diagnostic> diagnostics,
  ) {
    final configured = config.baseLocale;
    if (configured != null) {
      if (bundle.files.containsKey(configured)) {
        bundle.baseLocale = configured;
      } else {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCode.missingLocale,
            severity: Severity.error,
            message:
                'Base locale "$configured" has no file in ${bundle.id}; keys '
                'in this bundle cannot be compared.',
            locale: configured,
            bundle: bundle.id,
            suggestion:
                'Create ${bundle.id.replaceFirst('*', configured)} or choose '
                'another base locale.',
          ),
        );
      }
      return;
    }
    final template = '${project.l10n.arbDir}/${project.l10n.templateArbFile}';
    for (final file in bundle.files.values) {
      if (file.path == template) {
        bundle.baseLocale = file.locale;
        return;
      }
    }
    if (bundle.files.containsKey('en')) {
      bundle.baseLocale = 'en';
      return;
    }
    final locales = bundle.files.keys.toList()..sort();
    if (locales.isEmpty) return;
    bundle.baseLocale = locales.first;
    if (locales.length > 1) {
      diagnostics.add(
        Diagnostic(
          code: DiagnosticCode.configuration,
          severity: Severity.info,
          message:
              'No base locale configured for ${bundle.id}; using '
              '"${locales.first}" (first alphabetically).',
          bundle: bundle.id,
          suggestion: 'Set "base_locale" or pass --base-locale.',
        ),
      );
    }
  }

  bool _isSuppressed(Diagnostic d, AuditContext context) {
    if (!d.code.isSuppressible) return false;
    final key = d.key;
    if (key != null &&
        d.code != DiagnosticCode.duplicateKey &&
        context.isIgnoredKey(key)) {
      return true;
    }
    for (final rule in config.ignore.rules) {
      if (rule.code != null && rule.code != d.code) continue;
      if (rule.locale != null && rule.locale != d.locale) continue;
      if (rule.key != null && (key == null || !rule.key!.matches(key))) {
        continue;
      }
      if (rule.path != null) {
        final path = d.location?.path;
        if (path == null || !Glob(rule.path!, context: p.posix).matches(path)) {
          continue;
        }
      }
      return true;
    }
    return false;
  }

  Diagnostic _applyPolicy(Diagnostic d) {
    var result = d;
    final override = config.severityOverrides[d.code];
    if (override != null) result = result.copyWith(severity: override);
    final locale = d.locale;
    if (locale != null &&
        config.optionalLocales.contains(locale) &&
        !config.failOnOptionalLocales &&
        (d.code == DiagnosticCode.missingKey ||
            result.severity == Severity.warning)) {
      result = result.copyWith(severity: Severity.info);
    }
    return result;
  }
}
