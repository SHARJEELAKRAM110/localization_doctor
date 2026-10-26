import 'diagnostic.dart';

/// Supported translation file formats.
enum TranslationFormat {
  arb('arb'),
  json('json');

  const TranslationFormat(this.extension);

  /// File extension without the leading dot.
  final String extension;

  static TranslationFormat? tryParse(String value) {
    for (final format in TranslationFormat.values) {
      if (format.name == value) return format;
    }
    return null;
  }
}

/// The kind of value stored under a translation key.
enum EntryKind {
  /// A user-facing string.
  message,

  /// A value of an unsupported type (number, list, null, ...).
  invalid,
}

/// A single translation entry after parsing, keyed by its canonical key.
class TranslationEntry {
  const TranslationEntry({
    required this.key,
    required this.kind,
    required this.location,
    this.value,
    this.valueType,
  });

  /// Canonical key. Nested JSON keys are joined with the configured
  /// separator, e.g. `home.title`.
  final String key;
  final EntryKind kind;

  /// The string value, for [EntryKind.message].
  final String? value;

  /// The JSON type name of the value, for [EntryKind.invalid].
  final String? valueType;

  /// Location of the key in its file.
  final SourceLocation location;

  bool get isEmpty => kind == EntryKind.message && value!.trim().isEmpty;
}

/// A placeholder declared in ARB `@key.placeholders` metadata.
class PlaceholderMetadata {
  const PlaceholderMetadata(this.name, {this.type, this.format});

  final String name;
  final String? type;
  final String? format;
}

/// ARB `@key` metadata.
class ArbMetadata {
  const ArbMetadata({
    required this.key,
    required this.location,
    this.placeholders,
  });

  final String key;
  final SourceLocation location;

  /// Declared placeholders, or `null` when no `placeholders` object exists.
  final Map<String, PlaceholderMetadata>? placeholders;
}

/// A parsed translation file for one locale.
class TranslationFile {
  TranslationFile({
    required this.path,
    required this.format,
    required this.locale,
    required this.entries,
    this.metadata = const {},
    this.objectPaths = const {},
    this.declaredLocale,
    this.parseError,
  });

  /// Project-relative path using forward slashes.
  final String path;
  final TranslationFormat format;

  /// Locale identifier, normalized with underscores (`en_US`).
  final String locale;

  /// Entries by canonical key, in file order.
  final Map<String, TranslationEntry> entries;

  /// ARB metadata by message key.
  final Map<String, ArbMetadata> metadata;

  /// Canonical keys that hold nested objects (JSON only).
  final Map<String, SourceLocation> objectPaths;

  /// The `@@locale` value for ARB files, when present.
  final String? declaredLocale;

  /// Set when the file could not be parsed at all.
  final Diagnostic? parseError;

  bool get isValid => parseError == null;
}

/// A group of translation files that translate the same set of keys, such as
/// `lib/l10n/app_en.arb` and `lib/l10n/app_fr.arb`.
class TranslationBundle {
  TranslationBundle({
    required this.id,
    required this.directory,
    required this.format,
    required this.files,
  });

  /// Display id such as `lib/l10n/app_*.arb`.
  final String id;

  /// Project-relative directory.
  final String directory;
  final TranslationFormat format;

  /// Files by locale.
  final Map<String, TranslationFile> files;

  /// Base locale selected for this bundle; set by the auditor.
  String? baseLocale;

  TranslationFile? get baseFile =>
      baseLocale == null ? null : files[baseLocale];
}
