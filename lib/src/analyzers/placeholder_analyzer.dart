import '../discovery/locale_name.dart';
import '../models/diagnostic.dart';
import '../models/translation.dart';
import '../parsers/icu_parser.dart';
import 'audit_context.dart';

/// Validates message syntax (LOC010), placeholder consistency (LOC004) and
/// ARB metadata (LOC014).
///
/// Placeholders are compared only when both the base and the target message
/// parse cleanly, so a syntax error is never reported as a mismatch too.
class PlaceholderAnalyzer {
  PlaceholderAnalyzer(this.context);

  final AuditContext context;

  List<Diagnostic> analyze(TranslationBundle bundle) =>
      bundle.format == TranslationFormat.arb
      ? _analyzeArb(bundle)
      : _analyzeJson(bundle);

  String _list(Iterable<String> names) =>
      (names.toList()..sort()).map((n) => '{$n}').join(', ');

  List<Diagnostic> _analyzeArb(TranslationBundle bundle) {
    final diagnostics = <Diagnostic>[];
    final base = bundle.baseFile;
    final parsed = <String, Map<String, IcuParseResult>>{};

    for (final file in bundle.files.values) {
      if (!file.isValid) continue;
      final declared = file.declaredLocale;
      if (declared != null) {
        final normalized = normalizeLocale(declared);
        if (normalized != file.locale) {
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.arbMetadata,
              severity: Severity.warning,
              message:
                  '"@@locale" is "$declared" but the file is treated as '
                  '"${file.locale}".',
              location: SourceLocation(file.path),
              locale: file.locale,
              bundle: bundle.id,
              suggestion: 'Make "@@locale" match the locale in the file name.',
            ),
          );
        }
      }
      for (final meta in file.metadata.values) {
        if (!file.entries.containsKey(meta.key) &&
            !context.isIgnoredKey(meta.key)) {
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.arbMetadata,
              severity: Severity.warning,
              message:
                  'Metadata "@${meta.key}" has no matching message '
                  '"${meta.key}".',
              location: meta.location,
              key: meta.key,
              locale: file.locale,
              bundle: bundle.id,
              suggestion: 'Remove "@${meta.key}" or add the message.',
            ),
          );
        }
      }

      final results = parsed[file.locale] = {};
      for (final entry in file.entries.values) {
        if (entry.kind != EntryKind.message ||
            context.isIgnoredKey(entry.key)) {
          continue;
        }
        Set<String>? relaxed;
        if (context.relaxSyntax) {
          relaxed = {
            ...?base?.metadata[entry.key]?.placeholders?.keys,
            ...?file.metadata[entry.key]?.placeholders?.keys,
          };
        }
        final result = parseIcuMessage(
          entry.value!,
          useEscaping: context.useEscaping,
          relaxedPlaceholders: relaxed,
        );
        results[entry.key] = result;
        for (final error in result.errors) {
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.messageSyntax,
              severity: Severity.error,
              message:
                  'Invalid ICU message syntax in "${entry.key}" '
                  '(${file.locale}): $error.',
              location: entry.location,
              key: entry.key,
              locale: file.locale,
              bundle: bundle.id,
              suggestion: context.useEscaping
                  ? 'Balance the braces and quotes. Literal braces must be '
                        "quoted, e.g. '{'."
                  : 'Balance the braces. To use literal braces enable '
                        '"use-escaping: true" in l10n.yaml and quote them.',
            ),
          );
        }
        for (final warning in result.warnings) {
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.messageSyntax,
              severity: Severity.warning,
              message: '"${entry.key}" (${file.locale}): $warning.',
              location: entry.location,
              key: entry.key,
              locale: file.locale,
              bundle: bundle.id,
              suggestion: "Add an 'other' case.",
            ),
          );
        }
      }
    }

    if (base == null || !base.isValid) return diagnostics;
    final baseResults = parsed[base.locale]!;

    for (final entry in base.entries.values) {
      final key = entry.key;
      final baseResult = baseResults[key];
      if (baseResult == null || !baseResult.isValid) continue;
      final used = baseResult.arguments.keys.toSet();
      final declared = base.metadata[key]?.placeholders;

      if (declared != null) {
        final undeclared = used.difference(declared.keys.toSet());
        final unused = declared.keys.toSet().difference(used);
        if (undeclared.isNotEmpty) {
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.placeholderMismatch,
              severity: Severity.warning,
              message:
                  '"$key" uses ${_list(undeclared)} in ${base.locale} but '
                  '"@$key.placeholders" does not declare '
                  '${undeclared.length == 1 ? 'it' : 'them'}.',
              location: entry.location,
              key: key,
              locale: base.locale,
              bundle: bundle.id,
              suggestion: 'Declare ${_list(undeclared)} in "@$key".',
            ),
          );
        }
        if (unused.isNotEmpty) {
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.placeholderMismatch,
              severity: Severity.warning,
              message:
                  '"@$key.placeholders" declares ${_list(unused)} but the '
                  '${base.locale} message never uses '
                  '${unused.length == 1 ? 'it' : 'them'}.',
              location: base.metadata[key]!.location,
              key: key,
              locale: base.locale,
              bundle: bundle.id,
              suggestion: 'Use or remove the unused placeholder declaration.',
            ),
          );
        }
      }
      final allowed = {...used, ...?declared?.keys};

      for (final file in bundle.files.values) {
        if (file.locale == base.locale || !file.isValid) continue;
        final target = parsed[file.locale]?[key];
        final targetEntry = file.entries[key];
        if (target == null || targetEntry == null || !target.isValid) continue;
        final targetArgs = target.arguments.keys.toSet();
        final unexpected = targetArgs.difference(allowed);
        final missing = used.difference(targetArgs);
        if (unexpected.isNotEmpty) {
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.placeholderMismatch,
              severity: Severity.error,
              message:
                  '"$key" in ${file.locale} uses ${_list(unexpected)}, which '
                  '${unexpected.length == 1 ? 'is' : 'are'} not defined by '
                  'the base locale ${base.locale}.',
              location: targetEntry.location,
              relatedLocations: [entry.location],
              key: key,
              locale: file.locale,
              bundle: bundle.id,
              suggestion:
                  'Use only the placeholders of the base message: '
                  '${used.isEmpty ? '(none)' : _list(used)}.',
            ),
          );
        }
        if (missing.isNotEmpty) {
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.placeholderMismatch,
              severity: Severity.warning,
              message:
                  '"$key" in ${file.locale} does not use ${_list(missing)} '
                  'from the base locale ${base.locale}.',
              location: targetEntry.location,
              relatedLocations: [entry.location],
              key: key,
              locale: file.locale,
              bundle: bundle.id,
              suggestion:
                  'Include ${_list(missing)} in the translation, '
                  'unless omitting it is intentional.',
            ),
          );
        }
        for (final name in targetArgs.intersection(used)) {
          final baseKind = baseResult.arguments[name];
          final targetKind = target.arguments[name];
          if (baseKind != targetKind &&
              baseKind != IcuArgumentKind.simple &&
              targetKind != IcuArgumentKind.simple) {
            diagnostics.add(
              Diagnostic(
                code: DiagnosticCode.placeholderMismatch,
                severity: Severity.error,
                message:
                    '"$key": {$name} is used as ${baseKind!.name} in '
                    '${base.locale} but as ${targetKind!.name} in '
                    '${file.locale}.',
                location: targetEntry.location,
                key: key,
                locale: file.locale,
                bundle: bundle.id,
                suggestion: 'Use the same argument type as the base message.',
              ),
            );
          }
        }

        final targetDeclared = file.metadata[key]?.placeholders;
        if (declared != null && targetDeclared != null) {
          final differences = <String>[];
          final names = {...declared.keys, ...targetDeclared.keys}.toList()
            ..sort();
          for (final name in names) {
            final a = declared[name];
            final b = targetDeclared[name];
            if (a == null) {
              differences.add('{$name} is only declared in ${file.locale}');
            } else if (b == null) {
              differences.add('{$name} is not declared in ${file.locale}');
            } else if (a.type != b.type || a.format != b.format) {
              differences.add(
                '{$name} is ${_describe(a)} in ${base.locale} but '
                '${_describe(b)} in ${file.locale}',
              );
            }
          }
          if (differences.isNotEmpty) {
            diagnostics.add(
              Diagnostic(
                code: DiagnosticCode.placeholderMismatch,
                severity: Severity.warning,
                message:
                    'Placeholder metadata of "$key" differs: '
                    '${differences.join('; ')}.',
                location: file.metadata[key]!.location,
                key: key,
                locale: file.locale,
                bundle: bundle.id,
                suggestion:
                    'gen-l10n only reads metadata from the template '
                    'file; remove "@$key" from ${file.locale} or keep it '
                    'identical.',
              ),
            );
          }
        }
      }
    }
    return diagnostics;
  }

  String _describe(PlaceholderMetadata m) {
    final type = m.type ?? 'untyped';
    return m.format == null ? type : '$type (format ${m.format})';
  }

  List<Diagnostic> _analyzeJson(TranslationBundle bundle) {
    final diagnostics = <Diagnostic>[];
    final base = bundle.baseFile;
    if (base == null || !base.isValid) return diagnostics;
    final pattern = context.placeholderPattern;

    for (final entry in base.entries.values) {
      if (entry.kind != EntryKind.message || context.isIgnoredKey(entry.key)) {
        continue;
      }
      final expected = extractPatternPlaceholders(entry.value!, pattern);
      for (final file in bundle.files.values) {
        if (file.locale == base.locale || !file.isValid) continue;
        final target = file.entries[entry.key];
        if (target == null || target.kind != EntryKind.message) continue;
        final actual = extractPatternPlaceholders(target.value!, pattern);
        final unexpected = actual.named.difference(expected.named);
        final missing = expected.named.difference(actual.named);
        if (unexpected.isNotEmpty) {
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.placeholderMismatch,
              severity: Severity.error,
              message:
                  '"${entry.key}" in ${file.locale} uses '
                  '${_list(unexpected)}, which the base locale '
                  '${base.locale} does not define.',
              location: target.location,
              relatedLocations: [entry.location],
              key: entry.key,
              locale: file.locale,
              bundle: bundle.id,
              suggestion:
                  'Use only the placeholders of the base message: '
                  '${expected.named.isEmpty ? '(none)' : _list(expected.named)}.',
            ),
          );
        }
        if (missing.isNotEmpty) {
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.placeholderMismatch,
              severity: Severity.warning,
              message:
                  '"${entry.key}" in ${file.locale} does not use '
                  '${_list(missing)} from the base locale ${base.locale}.',
              location: target.location,
              relatedLocations: [entry.location],
              key: entry.key,
              locale: file.locale,
              bundle: bundle.id,
              suggestion: 'Include ${_list(missing)} in the translation.',
            ),
          );
        }
        if (actual.positionalCount != expected.positionalCount) {
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.placeholderMismatch,
              severity: Severity.warning,
              message:
                  '"${entry.key}" has ${actual.positionalCount} positional '
                  'placeholder(s) in ${file.locale} but '
                  '${expected.positionalCount} in ${base.locale}.',
              location: target.location,
              relatedLocations: [entry.location],
              key: entry.key,
              locale: file.locale,
              bundle: bundle.id,
              suggestion: 'Use the same number of positional placeholders.',
            ),
          );
        }
      }
    }
    return diagnostics;
  }
}
