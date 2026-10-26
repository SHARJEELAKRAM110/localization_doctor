import '../models/diagnostic.dart';
import '../models/translation.dart';
import '../source/usage_scanner.dart';
import 'audit_context.dart';

/// Classifies base-locale keys as used or unused (LOC002) and reports
/// dynamic lookups (LOC015) and undefined literal lookups (LOC016).
///
/// Classification for generated (ARB) keys:
/// * used: accessed on a localizations object (`AppLocalizations.of(...)`,
///   a variable holding it, or a configured accessor);
/// * inconclusive (info): the key's name appears as an identifier elsewhere;
/// * definite (warning): the name appears nowhere in the scanned sources;
/// * probable (info) instead of definite when no localization access was
///   recognized anywhere, which usually means an unconfigured accessor.
///
/// Classification for JSON keys:
/// * used: passed as a string literal to a lookup function;
/// * inconclusive (info): matches the literal prefix of a dynamic lookup
///   (`'errors.$code'.tr()`), or appears as a string literal elsewhere;
/// * probable (info): unreferenced, but lookups with unknown keys exist;
/// * definite (warning): unreferenced and every lookup used a literal key.
///
/// All results are relative to the scanned source directories; runtime usage
/// cannot be proven by static analysis.
class UnusedKeyAnalyzer {
  UnusedKeyAnalyzer(this.context, this.scan);

  final AuditContext context;
  final UsageScanResult scan;

  bool _ignored(String key) =>
      context.isIgnoredKey(key) ||
      context.config.ignore.unusedKeys.any((p) => p.matches(key));

  List<Diagnostic> analyze() {
    final diagnostics = <Diagnostic>[];
    if (scan.scannedFiles.isEmpty) {
      diagnostics.add(
        const Diagnostic(
          code: DiagnosticCode.configuration,
          severity: Severity.info,
          message:
              'No Dart source files were scanned, so unused-key '
              'analysis was skipped.',
          suggestion:
              'Set "source.directories" to the folders containing '
              'your Dart code.',
        ),
      );
      return diagnostics;
    }

    final hasArb = context.bundles.any(
      (b) => b.format == TranslationFormat.arb,
    );
    final hasJson = context.bundles.any(
      (b) => b.format == TranslationFormat.json,
    );
    final noAccessFound = scan.generatedMembers.isEmpty;
    if (hasArb && noAccessFound) {
      diagnostics.add(
        Diagnostic(
          code: DiagnosticCode.configuration,
          severity: Severity.info,
          message:
              'No access through ${context.localizationClasses.join(', ')} '
              'was found in ${scan.scannedFiles.length} scanned Dart file(s); '
              'unused ARB keys are reported as probable only.',
          suggestion:
              'If you use an accessor such as `context.l10n`, add it '
              'to "source.accessors".',
        ),
      );
    }

    final unknownDynamic = scan.dynamicLookups
        .where((d) => d.prefix.isEmpty)
        .isNotEmpty;

    for (final bundle in context.bundles) {
      final base = bundle.baseFile;
      if (base == null || !base.isValid) continue;
      for (final key in base.entries.keys) {
        if (_ignored(key)) continue;
        Confidence? confidence;
        String reason;
        if (bundle.format == TranslationFormat.arb) {
          if (scan.generatedMembers.containsKey(key)) continue;
          if (scan.identifiers.contains(key)) {
            confidence = Confidence.inconclusive;
            reason =
                'it is not accessed through a recognized localizations '
                'object, but an identifier with the same name exists';
          } else if (noAccessFound) {
            confidence = Confidence.probable;
            reason = 'no localization access was recognized in the sources';
          } else {
            confidence = Confidence.definite;
            reason = 'its getter is never referenced in the scanned sources';
          }
        } else {
          if (scan.literalLookups.containsKey(key)) continue;
          final prefixMatch = scan.dynamicLookups.any(
            (d) => d.prefix.isNotEmpty && key.startsWith(d.prefix),
          );
          if (prefixMatch) {
            confidence = Confidence.inconclusive;
            reason = 'it matches the prefix of a dynamic lookup';
          } else if (scan.stringLiterals.contains(key)) {
            confidence = Confidence.inconclusive;
            reason =
                'it is not passed directly to a lookup function, but the '
                'same string literal exists in the sources';
          } else if (unknownDynamic) {
            confidence = Confidence.probable;
            reason =
                'it is never referenced, but some lookups use keys that '
                'cannot be determined statically';
          } else {
            confidence = Confidence.definite;
            reason = 'it is never referenced in the scanned sources';
          }
        }
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCode.unusedKey,
            severity: confidence == Confidence.definite
                ? Severity.warning
                : Severity.info,
            confidence: confidence,
            message: 'Key "$key" appears to be unused: $reason.',
            location: base.entries[key]!.location,
            key: key,
            locale: base.locale,
            bundle: bundle.id,
            suggestion: confidence == Confidence.definite
                ? 'Remove "$key" from every locale, or add it to '
                      '"ignore.unused_keys" if it is used dynamically.'
                : 'Verify manually; add "$key" to "ignore.unused_keys" if '
                      'it is used.',
          ),
        );
      }
    }

    if (hasJson) {
      for (final lookup in scan.dynamicLookups) {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCode.dynamicKeyUsage,
            severity: Severity.info,
            confidence: Confidence.definite,
            message: lookup.prefix.isEmpty
                ? 'Translation lookup with a key that cannot be determined '
                      'statically.'
                : 'Dynamic translation lookup; keys starting with '
                      '"${lookup.prefix}" are treated as possibly used.',
            location: lookup.location,
            suggestion: 'List keys used this way in "ignore.unused_keys".',
          ),
        );
      }

      final defined = <String>{};
      for (final bundle in context.bundles) {
        if (bundle.format != TranslationFormat.json) continue;
        final base = bundle.baseFile;
        if (base == null) continue;
        defined
          ..addAll(base.entries.keys)
          ..addAll(base.objectPaths.keys);
      }
      final keys = scan.literalLookups.keys.toList()..sort();
      for (final key in keys) {
        if (defined.contains(key) || context.isIgnoredKey(key)) continue;
        for (final location in scan.literalLookups[key]!) {
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.undefinedKey,
              severity: Severity.warning,
              confidence: Confidence.probable,
              message:
                  'Key "$key" is looked up in source but is not defined in '
                  'any base-locale JSON file.',
              location: location,
              key: key,
              suggestion: 'Add "$key" to the base locale or fix the typo.',
            ),
          );
        }
      }
    }
    return diagnostics;
  }
}
