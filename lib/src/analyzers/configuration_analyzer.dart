import 'dart:io';

import 'package:path/path.dart' as p;

import '../discovery/locale_name.dart';
import '../models/diagnostic.dart';
import '../models/translation.dart';
import '../source/usage_scanner.dart';
import 'audit_context.dart';

/// Checks Flutter localization configuration (LOC007). Never modifies the
/// project; only reports what it can detect reliably.
class ConfigurationAnalyzer {
  ConfigurationAnalyzer(this.context, this.scan, this.searchedDirectories);

  final AuditContext context;
  final UsageScanResult? scan;
  final List<String> searchedDirectories;

  Diagnostic _issue(
    Severity severity,
    String message, {
    String? suggestion,
    SourceLocation? location,
    Confidence confidence = Confidence.definite,
    String? locale,
    String? bundle,
  }) => Diagnostic(
    code: DiagnosticCode.configuration,
    severity: severity,
    confidence: confidence,
    message: message,
    suggestion: suggestion,
    location: location,
    locale: locale,
    bundle: bundle,
  );

  List<Diagnostic> analyze() {
    final project = context.project;
    final l10n = project.l10n;
    final diagnostics = <Diagnostic>[];

    if (!project.hasPubspec) {
      diagnostics.add(
        _issue(
          Severity.warning,
          'No pubspec.yaml found in the project root.',
          suggestion: 'Run the audit from the package root or pass --path.',
        ),
      );
    } else if (project.pubspecError != null) {
      diagnostics.add(
        _issue(
          Severity.error,
          'pubspec.yaml could not be parsed: ${project.pubspecError}.',
          location: const SourceLocation('pubspec.yaml'),
        ),
      );
    }

    if (context.bundles.isEmpty) {
      diagnostics.add(
        _issue(
          Severity.error,
          searchedDirectories.isEmpty
              ? 'No localization directory was found.'
              : 'No translation files were found in '
                    '${searchedDirectories.join(', ')}.',
          suggestion:
              'Set "localization.directories" in '
              'localization_doctor.yaml, or run `localization_doctor init`.',
        ),
      );
    }

    if (l10n.error != null) {
      diagnostics.add(
        _issue(
          Severity.error,
          'l10n.yaml could not be parsed: ${l10n.error}.',
          location: const SourceLocation('l10n.yaml'),
        ),
      );
    }

    final arbBundles = context.bundles
        .where((b) => b.format == TranslationFormat.arb)
        .toList();
    final usesGenL10n = l10n.exists || arbBundles.isNotEmpty;

    if (project.isFlutter && usesGenL10n) {
      if (!project.generateFlag) {
        diagnostics.add(
          _issue(
            Severity.warning,
            'pubspec.yaml does not set `flutter: generate: true`; '
            '`flutter gen-l10n` refuses to generate localizations without it.',
            location: const SourceLocation('pubspec.yaml'),
            suggestion: 'Add `generate: true` under the `flutter:` section.',
          ),
        );
      }
      for (final dep in ['flutter_localizations', 'intl']) {
        if (!project.dependencies.contains(dep)) {
          diagnostics.add(
            _issue(
              Severity.warning,
              'pubspec.yaml does not depend on `$dep`, which the generated '
              'localizations code requires.',
              location: const SourceLocation('pubspec.yaml'),
              suggestion: dep == 'intl'
                  ? 'Run `flutter pub add intl:any`.'
                  : 'Add `$dep: {sdk: flutter}` to dependencies.',
            ),
          );
        }
      }
    }

    if (l10n.exists && l10n.error == null) {
      diagnostics.addAll(_checkL10nYaml(arbBundles));
    }

    diagnostics.addAll(_checkSupportedLocales());
    diagnostics.addAll(_checkJsonAssets());
    return diagnostics;
  }

  List<Diagnostic> _checkL10nYaml(List<TranslationBundle> arbBundles) {
    final l10n = context.project.l10n;
    final root = context.root;
    final diagnostics = <Diagnostic>[];
    const location = SourceLocation('l10n.yaml');

    if (l10n.syntheticPackage == true) {
      diagnostics.add(
        _issue(
          Severity.error,
          'l10n.yaml enables `synthetic-package`, which current Flutter '
          'versions no longer support.',
          location: location,
          suggestion:
              'Remove `synthetic-package` and import the generated '
              'file from its output directory.',
        ),
      );
    } else if (l10n.syntheticPackage == false) {
      diagnostics.add(
        _issue(
          Severity.info,
          '`synthetic-package: false` no longer has any effect.',
          location: location,
          suggestion: 'Remove `synthetic-package` from l10n.yaml.',
        ),
      );
    }

    final arbDir = Directory(p.join(root, l10n.arbDir));
    if (!arbDir.existsSync()) {
      diagnostics.add(
        _issue(
          Severity.error,
          'The arb-dir "${l10n.arbDir}" configured in l10n.yaml does not '
          'exist.',
          location: location,
          suggestion: 'Fix `arb-dir` in l10n.yaml.',
        ),
      );
      return diagnostics;
    }
    final templatePath = '${l10n.arbDir}/${l10n.templateArbFile}';
    if (!File(p.join(root, templatePath)).existsSync()) {
      diagnostics.add(
        _issue(
          Severity.error,
          'The template-arb-file "$templatePath" does not exist.',
          location: location,
          suggestion: 'Fix `template-arb-file` in l10n.yaml.',
        ),
      );
      return diagnostics;
    }

    TranslationBundle? genBundle;
    for (final bundle in arbBundles) {
      if (bundle.files.values.any((f) => f.path == templatePath)) {
        genBundle = bundle;
      }
    }
    if (genBundle == null) return diagnostics;

    final templateLocale = genBundle.files.values
        .firstWhere((f) => f.path == templatePath)
        .locale;
    if (genBundle.baseLocale != null &&
        genBundle.baseLocale != templateLocale) {
      diagnostics.add(
        _issue(
          Severity.warning,
          'l10n.yaml uses "$templatePath" ($templateLocale) as the template, '
          'but the audit uses ${genBundle.baseLocale} as the base locale.',
          location: location,
          bundle: genBundle.id,
          suggestion:
              'Use --base-locale $templateLocale (or base_locale) so '
              'the audit matches code generation.',
        ),
      );
    }

    final outputDir = l10n.effectiveOutputDir;
    final outputPath = '$outputDir/${l10n.outputLocalizationFile}';
    final outputFile = File(p.join(root, outputPath));
    if (!outputFile.existsSync()) {
      diagnostics.add(
        _issue(
          Severity.info,
          'Generated localizations file "$outputPath" was not found. It is '
          'created by `flutter gen-l10n` (or automatically by '
          '`flutter pub get`).',
          confidence: Confidence.probable,
          location: location,
          bundle: genBundle.id,
          suggestion:
              'Run `flutter gen-l10n` if the generated code is '
              'expected to be checked in.',
        ),
      );
      return diagnostics;
    }

    final stem = p.basenameWithoutExtension(l10n.outputLocalizationFile);
    final languages = {
      for (final f in genBundle.files.values) languageOf(f.locale),
    }.toList()..sort();
    final missingLanguages = [
      for (final language in languages)
        if (!File(
          p.join(root, outputDir, '${stem}_$language.dart'),
        ).existsSync())
          language,
    ];
    if (missingLanguages.isNotEmpty) {
      diagnostics.add(
        _issue(
          Severity.warning,
          'Generated localizations in "$outputDir" are stale: no generated '
          'file for ${missingLanguages.join(', ')}.',
          location: SourceLocation(outputPath),
          bundle: genBundle.id,
          suggestion: 'Run `flutter gen-l10n`.',
        ),
      );
    } else {
      final generatedAt = outputFile.lastModifiedSync();
      final newer = [
        for (final f in genBundle.files.values)
          if (File(
            p.join(root, f.path),
          ).lastModifiedSync().isAfter(generatedAt))
            f.path,
      ]..sort();
      if (newer.isNotEmpty) {
        diagnostics.add(
          _issue(
            Severity.info,
            'Generated localizations may be stale: ${newer.join(', ')} '
            '${newer.length == 1 ? 'was' : 'were'} modified after '
            '"$outputPath".',
            confidence: Confidence.probable,
            location: SourceLocation(outputPath),
            bundle: genBundle.id,
            suggestion: 'Run `flutter gen-l10n`.',
          ),
        );
      }
    }
    return diagnostics;
  }

  List<Diagnostic> _checkSupportedLocales() {
    final declarations = scan?.supportedLocales ?? const [];
    if (declarations.isEmpty || context.bundles.isEmpty) return const [];
    final available = {
      for (final bundle in context.bundles) ...bundle.files.keys,
    };
    bool covered(String locale, Iterable<String> pool) =>
        pool.contains(locale) ||
        pool.any((l) => languageOf(l) == languageOf(locale));

    final diagnostics = <Diagnostic>[];
    for (final declaration in declarations) {
      final listed = declaration.locales;
      for (final locale in listed) {
        if (!covered(locale, available)) {
          diagnostics.add(
            _issue(
              Severity.warning,
              'supportedLocales lists "$locale", but no translation file '
              'exists for it.',
              location: declaration.location,
              locale: locale,
              suggestion:
                  'Add translations for "$locale" or remove it from '
                  'supportedLocales.',
            ),
          );
        }
      }
      final missing = available.where((l) => !covered(l, listed)).toList()
        ..sort();
      for (final locale in missing) {
        diagnostics.add(
          _issue(
            Severity.warning,
            'Translations exist for "$locale", but supportedLocales does not '
            'list it, so the app will never use them.',
            location: declaration.location,
            locale: locale,
            suggestion:
                'Add the locale to supportedLocales, or use '
                '`AppLocalizations.supportedLocales`.',
          ),
        );
      }
    }
    return diagnostics;
  }

  List<Diagnostic> _checkJsonAssets() {
    final project = context.project;
    if (!project.isFlutter) return const [];
    final diagnostics = <Diagnostic>[];
    for (final bundle in context.bundles) {
      if (bundle.format != TranslationFormat.json) continue;
      if (!bundle.directory.startsWith('assets/')) continue;
      final undeclared = [
        for (final file in bundle.files.values)
          if (!project.assets.any(
            (asset) =>
                asset == file.path ||
                (asset.endsWith('/') &&
                    p.posix.normalize(asset) == p.posix.dirname(file.path)),
          ))
            file.path,
      ]..sort();
      if (undeclared.isEmpty) continue;
      diagnostics.add(
        _issue(
          Severity.warning,
          'JSON translations are not declared as Flutter assets: '
          '${undeclared.join(', ')}. Runtime loaders cannot read them.',
          confidence: Confidence.probable,
          location: const SourceLocation('pubspec.yaml'),
          bundle: bundle.id,
          suggestion:
              'Add "${bundle.directory}/" under `flutter: assets:` '
              'in pubspec.yaml.',
        ),
      );
    }
    return diagnostics;
  }
}
