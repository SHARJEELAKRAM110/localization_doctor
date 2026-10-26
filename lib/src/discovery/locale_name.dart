/// Locale identifier helpers.
///
/// Locales are normalized to underscore form: `language[_Script][_REGION]`,
/// for example `en`, `en_US`, `zh_Hant_TW`.
library;

final _language = RegExp(r'^[a-zA-Z]{2,3}$');
final _script = RegExp(r'^[a-zA-Z]{4}$');
final _region = RegExp(r'^(?:[a-zA-Z]{2}|[0-9]{3})$');
final _strictLanguage = RegExp(r'^[a-z]{2,3}$');
final _strictScript = RegExp(r'^[A-Z][a-z]{3}$');
final _strictRegion = RegExp(r'^(?:[A-Z]{2}|[0-9]{3})$');

/// Normalizes a locale identifier written with `_` or `-` separators and
/// any casing. Returns `null` when [value] is not a valid identifier.
String? normalizeLocale(String value) {
  final parts = value.trim().split(RegExp('[-_]'));
  if (parts.isEmpty || parts.length > 3) return null;
  if (!_language.hasMatch(parts[0])) return null;
  final result = [parts[0].toLowerCase()];
  var index = 1;
  if (index < parts.length && _script.hasMatch(parts[index])) {
    final s = parts[index];
    result.add(s[0].toUpperCase() + s.substring(1).toLowerCase());
    index++;
  }
  if (index < parts.length && _region.hasMatch(parts[index])) {
    result.add(parts[index].toUpperCase());
    index++;
  }
  if (index != parts.length) return null;
  return result.join('_');
}

/// The language part of a normalized locale (`en_US` -> `en`).
String languageOf(String locale) => locale.split('_').first;

/// Result of detecting a locale in a file name.
class FileLocale {
  const FileLocale(this.prefix, this.locale);

  /// File name part before the locale, including the trailing separator
  /// (`app_` for `app_en_US.arb`, empty for `en.json`).
  final String prefix;
  final String locale;
}

/// Detects the locale at the end of a file name without extension.
///
/// Supports `app_en`, `app_en_US`, `intl_zh_Hant_TW`, `en`, `en-US` and
/// `pt_BR`. When the locale follows a prefix, its casing must be canonical
/// (`en_US`, not `en_us`) so that a word like `app` in `app_en` is never
/// mistaken for a language code.
FileLocale? detectLocaleFromFileName(String stem) {
  final tokens = stem.split(RegExp('[-_]'));
  // A whole-name locale needs a two-letter language when it has more than
  // one part, so `app_EN` is not read as language "app" with region "EN".
  final wholeAllowed = tokens.length == 1 || tokens.first.length == 2;
  if (wholeAllowed && _isStrictLocale(tokens)) {
    return FileLocale('', tokens.join('_'));
  }

  for (var length = 3; length >= 1; length--) {
    if (tokens.length <= length) continue;
    final candidate = tokens.sublist(tokens.length - length);
    if (!_isStrictLocale(candidate)) continue;
    final prefixLength = stem.length - candidate.join('_').length;
    final prefix = stem.substring(0, prefixLength);
    // `en-us`: a two-letter "prefix" is far more likely a language code.
    if (prefixLength == 3 && normalizeLocale(stem) != null) break;
    return FileLocale(prefix, candidate.join('_'));
  }
  if (wholeAllowed) {
    final whole = normalizeLocale(stem);
    if (whole != null) return FileLocale('', whole);
  }
  return null;
}

bool _isStrictLocaleLength(List<String> parts) =>
    parts.isNotEmpty && parts.length <= 3;

bool _isStrictLocale(List<String> parts) {
  if (!_isStrictLocaleLength(parts)) return false;
  if (!_strictLanguage.hasMatch(parts[0])) return false;
  if (parts.length == 1) return true;
  if (parts.length == 2) {
    return _strictScript.hasMatch(parts[1]) || _strictRegion.hasMatch(parts[1]);
  }
  return _strictScript.hasMatch(parts[1]) && _strictRegion.hasMatch(parts[2]);
}
