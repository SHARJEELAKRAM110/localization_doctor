import '../models/diagnostic.dart';
import '../models/translation.dart';

/// Default regular expression for JSON placeholders: `{name}`.
const defaultJsonPlaceholderPattern = r'\{([A-Za-z_][A-Za-z0-9_]*)\}';

/// Default Dart method names treated as JSON key lookups, covering
/// easy_localization (`'key'.tr()`, `tr('key')`, `plural('key', n)`) and
/// GetX (`'key'.tr`).
const defaultJsonLookupFunctions = ['tr', 'plural', 'translate'];

/// Default classes whose `static const` strings are translation keys:
/// easy_localization's generated `LocaleKeys`.
const defaultKeyClasses = ['LocaleKeys'];

/// Directories excluded from source scanning in addition to user excludes.
const defaultSourceExcludes = [
  '**/*.g.dart',
  '**/*.freezed.dart',
  '**/*.gr.dart',
  '**/*.config.dart',
  '**/*.mocks.dart',
  '**/generated/**',
];

/// Candidate localization directories probed when none are configured.
const defaultLocalizationDirectories = [
  'lib/l10n',
  'lib/src/l10n',
  'lib/i18n',
  'l10n',
  'assets/translations',
  'assets/i18n',
  'assets/l10n',
  'assets/lang',
  'assets/langs',
  'assets/locales',
  'i18n',
  'translations',
];

/// Which checks run. All are enabled by default.
class ChecksConfig {
  const ChecksConfig({
    this.missingKeys = true,
    this.extraKeys = true,
    this.unusedKeys = true,
    this.duplicateKeys = true,
    this.placeholderMismatches = true,
    this.emptyValues = true,
    this.messageSyntax = true,
    this.configuration = true,
  });

  final bool missingKeys;
  final bool extraKeys;
  final bool unusedKeys;
  final bool duplicateKeys;
  final bool placeholderMismatches;
  final bool emptyValues;
  final bool messageSyntax;
  final bool configuration;

  static const names = [
    'missing_keys',
    'extra_keys',
    'unused_keys',
    'duplicate_keys',
    'placeholder_mismatches',
    'empty_values',
    'message_syntax',
    'configuration',
  ];

  /// Codes produced by each check, used to filter disabled checks.
  bool isEnabled(DiagnosticCode code) => switch (code) {
    DiagnosticCode.missingKey || DiagnosticCode.missingLocale => missingKeys,
    DiagnosticCode.extraKey => extraKeys,
    DiagnosticCode.unusedKey ||
    DiagnosticCode.dynamicKeyUsage ||
    DiagnosticCode.undefinedKey => unusedKeys,
    DiagnosticCode.duplicateKey => duplicateKeys,
    DiagnosticCode.placeholderMismatch => placeholderMismatches,
    DiagnosticCode.emptyValue || DiagnosticCode.emptyLocaleFile => emptyValues,
    DiagnosticCode.messageSyntax => messageSyntax,
    DiagnosticCode.configuration => configuration,
    // Parse failures, value types, structure and metadata problems are
    // always reported.
    DiagnosticCode.invalidFile ||
    DiagnosticCode.invalidValueType ||
    DiagnosticCode.structureMismatch ||
    DiagnosticCode.arbMetadata => true,
  };
}

/// A single "known exception" rule. Every field that is set must match.
class IgnoreRule {
  const IgnoreRule({this.code, this.key, this.locale, this.path});

  final DiagnosticCode? code;
  final KeyPattern? key;
  final String? locale;

  /// Glob matched against the diagnostic's project-relative path.
  final String? path;
}

/// A key pattern where `*` matches any sequence of characters (including
/// the key separator) and `?` matches one character. Without wildcards the
/// pattern matches the key exactly.
class KeyPattern {
  KeyPattern(this.source) : _regex = _compile(source);

  final String source;
  final RegExp _regex;

  bool matches(String key) => _regex.hasMatch(key);

  static RegExp _compile(String pattern) {
    final buffer = StringBuffer('^');
    for (final char in pattern.split('')) {
      buffer.write(switch (char) {
        '*' => '.*',
        '?' => '.',
        _ => RegExp.escape(char),
      });
    }
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }
}

/// Ignore rules. See README "Ignore rules" for exact semantics.
class IgnoreConfig {
  const IgnoreConfig({
    this.keys = const [],
    this.unusedKeys = const [],
    this.rules = const [],
  });

  /// Keys excluded from every key-level check and from coverage totals.
  /// Duplicate-key and parse diagnostics are still reported.
  final List<KeyPattern> keys;

  /// Keys never reported as unused (for example keys built dynamically).
  final List<KeyPattern> unusedKeys;

  /// Specific known exceptions.
  final List<IgnoreRule> rules;
}

/// Fully validated configuration with defaults applied.
class DoctorConfig {
  const DoctorConfig({
    this.baseLocale,
    this.directories,
    this.formats = const {TranslationFormat.arb, TranslationFormat.json},
    this.requiredLocales = const [],
    this.optionalLocales = const [],
    this.failOnOptionalLocales = false,
    this.localeMappings = const {},
    this.keySeparator = '.',
    this.jsonPlaceholderPattern = defaultJsonPlaceholderPattern,
    this.arbUseEscaping,
    this.arbRelaxSyntax,
    this.sourceDirectories = const ['lib'],
    this.explicitSourceDirectories = false,
    this.sourceExclude = const [],
    this.localizationClasses,
    this.accessors = const [],
    this.jsonLookupFunctions = defaultJsonLookupFunctions,
    this.keyClasses = defaultKeyClasses,
    this.checks = const ChecksConfig(),
    this.ignore = const IgnoreConfig(),
    this.severityOverrides = const {},
    this.failOn = Severity.error,
    this.reportFormats = const ['terminal'],
    this.outputDirectory,
    this.configPath,
  });

  /// Reference locale. `null` means auto-detect.
  final String? baseLocale;

  /// Project-relative localization directories. `null` means auto-detect.
  final List<String>? directories;
  final Set<TranslationFormat> formats;
  final List<String> requiredLocales;
  final List<String> optionalLocales;

  /// When true, optional locales are held to the same severities as
  /// required ones.
  final bool failOnOptionalLocales;

  /// Explicit project-relative file path -> locale mappings.
  final Map<String, String> localeMappings;
  final String keySeparator;
  final String jsonPlaceholderPattern;

  /// `null` means "read from l10n.yaml".
  final bool? arbUseEscaping;
  final bool? arbRelaxSyntax;
  final List<String> sourceDirectories;

  /// Whether [sourceDirectories] came from the configuration file. Missing
  /// directories are only reported when they were configured explicitly.
  final bool explicitSourceDirectories;
  final List<String> sourceExclude;

  /// Generated localization class names. `null` means "read from l10n.yaml,
  /// falling back to AppLocalizations".
  final List<String>? localizationClasses;

  /// Extra expressions that evaluate to the localizations object, such as
  /// `context.l10n`.
  final List<String> accessors;
  final List<String> jsonLookupFunctions;

  /// Classes whose `static const` string fields are translation keys.
  final List<String> keyClasses;
  final ChecksConfig checks;
  final IgnoreConfig ignore;
  final Map<DiagnosticCode, Severity> severityOverrides;

  /// Lowest severity that fails the audit. `--strict` lowers it to warning.
  final Severity failOn;
  final List<String> reportFormats;
  final String? outputDirectory;

  /// Path of the file this configuration was loaded from, if any.
  final String? configPath;

  DoctorConfig copyWith({
    String? baseLocale,
    Severity? failOn,
    List<String>? reportFormats,
    String? outputDirectory,
  }) => DoctorConfig(
    baseLocale: baseLocale ?? this.baseLocale,
    directories: directories,
    formats: formats,
    requiredLocales: requiredLocales,
    optionalLocales: optionalLocales,
    failOnOptionalLocales: failOnOptionalLocales,
    localeMappings: localeMappings,
    keySeparator: keySeparator,
    jsonPlaceholderPattern: jsonPlaceholderPattern,
    arbUseEscaping: arbUseEscaping,
    arbRelaxSyntax: arbRelaxSyntax,
    sourceDirectories: sourceDirectories,
    explicitSourceDirectories: explicitSourceDirectories,
    sourceExclude: sourceExclude,
    localizationClasses: localizationClasses,
    accessors: accessors,
    jsonLookupFunctions: jsonLookupFunctions,
    keyClasses: keyClasses,
    checks: checks,
    ignore: ignore,
    severityOverrides: severityOverrides,
    failOn: failOn ?? this.failOn,
    reportFormats: reportFormats ?? this.reportFormats,
    outputDirectory: outputDirectory ?? this.outputDirectory,
    configPath: configPath,
  );
}
