import 'package:path/path.dart' as p;

import '../models/audit_result.dart';
import '../models/diagnostic.dart';
import '../models/translation.dart';
import 'audit_context.dart';

/// Compares every locale of a bundle with its base locale.
///
/// Produces LOC001 (missing), LOC005 (empty value), LOC008 (extra key),
/// LOC011 (structure mismatch), LOC012 (empty file) and LOC013 (missing
/// required locale), and computes [LocaleCoverage].
class MissingKeyAnalyzer {
  MissingKeyAnalyzer(this.context);

  final AuditContext context;

  final coverage = <LocaleCoverage>[];

  List<Diagnostic> analyze(TranslationBundle bundle) {
    final diagnostics = <Diagnostic>[];
    final base = bundle.baseFile;
    final separator = bundle.format == TranslationFormat.json
        ? context.config.keySeparator
        : null;

    for (final locale in context.config.requiredLocales) {
      if (!bundle.files.containsKey(locale)) {
        final example = _exampleFileName(bundle, locale);
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCode.missingLocale,
            severity: Severity.error,
            message:
                'Required locale "$locale" has no translation file in '
                '${bundle.id}.',
            locale: locale,
            bundle: bundle.id,
            suggestion: 'Create $example.',
          ),
        );
      }
    }

    for (final file in bundle.files.values) {
      if (!file.isValid) continue;
      if (file.entries.isEmpty) {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCode.emptyLocaleFile,
            severity: Severity.warning,
            message: '${file.path} contains no translations.',
            location: SourceLocation(file.path),
            locale: file.locale,
            bundle: bundle.id,
            suggestion: 'Add translations or remove the file.',
          ),
        );
      }
      for (final entry in file.entries.values) {
        if (entry.isEmpty && !context.isIgnoredKey(entry.key)) {
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.emptyValue,
              severity: Severity.warning,
              message: 'Translation "${entry.key}" is empty in ${file.locale}.',
              location: entry.location,
              key: entry.key,
              locale: file.locale,
              bundle: bundle.id,
              suggestion: 'Provide a translation for "${entry.key}".',
            ),
          );
        }
      }
    }

    if (base == null || !base.isValid) return diagnostics;

    final baseKeys = [
      for (final key in base.entries.keys)
        if (!context.isIgnoredKey(key)) key,
    ];

    for (final file in bundle.files.values) {
      final isBase = file.locale == base.locale;
      if (!file.isValid) {
        coverage.add(
          LocaleCoverage(
            bundle: bundle.id,
            locale: file.locale,
            isBase: isBase,
            isOptional: context.isOptional(file.locale),
            total: baseKeys.length,
            translated: 0,
            missing: baseKeys.length,
            empty: 0,
            invalid: 0,
            fileValid: false,
          ),
        );
        continue;
      }

      final mismatchRoots = <String>[];
      if (!isBase) {
        void structure(String key, SourceLocation location, String objectIn) {
          if (context.isIgnoredKey(key)) return;
          mismatchRoots.add(key);
          final other = objectIn == 'base' ? file.locale : base.locale;
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.structureMismatch,
              severity: Severity.error,
              message:
                  '"$key" is a nested object in the $objectIn locale '
                  '(${objectIn == 'base' ? base.locale : file.locale}) but a '
                  'single value in $other.',
              location: location,
              key: key,
              locale: file.locale,
              bundle: bundle.id,
              suggestion:
                  'Use the same nesting for "$key" as the base '
                  'locale ${base.locale}.',
            ),
          );
        }

        for (final key in base.objectPaths.keys) {
          final entry = file.entries[key];
          if (entry != null) structure(key, entry.location, 'base');
        }
        for (final entry in file.objectPaths.entries) {
          if (base.entries.containsKey(entry.key)) {
            structure(entry.key, entry.value, 'target');
          }
        }
      }

      bool underMismatch(String key) => mismatchRoots.any(
        (root) => key == root || key.startsWith('$root$separator'),
      );

      var translated = 0;
      var missing = 0;
      var empty = 0;
      var invalid = 0;
      for (final key in baseKeys) {
        final entry = file.entries[key];
        if (entry == null) {
          missing++;
          if (!underMismatch(key)) {
            diagnostics.add(
              Diagnostic(
                code: DiagnosticCode.missingKey,
                severity: Severity.error,
                message:
                    'Key "$key" exists in ${base.locale} but is missing '
                    'from ${file.locale}.',
                location: SourceLocation(file.path),
                relatedLocations: [base.entries[key]!.location],
                key: key,
                locale: file.locale,
                bundle: bundle.id,
                suggestion: 'Add "$key" to ${p.posix.basename(file.path)}.',
              ),
            );
          }
        } else if (entry.kind == EntryKind.invalid) {
          invalid++;
        } else if (entry.isEmpty) {
          empty++;
        } else {
          translated++;
        }
      }

      if (!isBase) {
        for (final entry in file.entries.values) {
          final key = entry.key;
          if (base.entries.containsKey(key) ||
              context.isIgnoredKey(key) ||
              underMismatch(key)) {
            continue;
          }
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.extraKey,
              severity: Severity.warning,
              message:
                  'Key "$key" exists in ${file.locale} but not in the base '
                  'locale ${base.locale}.',
              location: entry.location,
              key: key,
              locale: file.locale,
              bundle: bundle.id,
              suggestion: 'Remove "$key" or add it to the base locale.',
            ),
          );
        }
      }

      coverage.add(
        LocaleCoverage(
          bundle: bundle.id,
          locale: file.locale,
          isBase: isBase,
          isOptional: context.isOptional(file.locale),
          total: baseKeys.length,
          translated: translated,
          missing: missing,
          empty: empty,
          invalid: invalid,
        ),
      );
    }
    return diagnostics;
  }

  String _exampleFileName(TranslationBundle bundle, String locale) =>
      bundle.id.replaceFirst('*', locale);
}
