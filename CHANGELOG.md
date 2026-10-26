# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

- Unused-key analysis understands easy_localization's generated `LocaleKeys`
  constants (`tr(LocaleKeys.home_title)`, `LocaleKeys.home_title.tr()`).
  Classes are configurable with `source.key_classes` (default
  `[LocaleKeys]`). References to constants whose key is missing from the base
  JSON are reported as `LOC016`.
- `init` writes `key_classes` for JSON projects.
- README: recommend `--output-dir` over `>` on Windows PowerShell 5.1.

## 0.2.0

Initial release.

- Discovery of ARB and JSON translation files, with locale detection from
  file names, ARB `@@locale`, or explicit `locale_mappings`.
- Location-aware JSON parser that detects duplicate keys before they are
  discarded, at every nesting level (LOC003).
- Missing keys (LOC001), keys missing from the base locale (LOC008), empty
  values (LOC005), invalid value types (LOC009), nested-structure mismatches
  (LOC011), empty locale files (LOC012) and missing required locales (LOC013).
- ICU message validation for ARB files following Flutter `gen-l10n` rules,
  including `use-escaping` and `relax-syntax` (LOC010).
- Placeholder comparison for ARB (including `@key.placeholders` metadata) and
  for JSON with a configurable pattern (LOC004), plus ARB metadata checks
  (LOC014).
- Unused-key analysis based on `package:analyzer` ASTs for generated
  localizations (`AppLocalizations.of(context)!.key`, variables, fields,
  parameters, custom accessors) and JSON lookups (`'key'.tr()`, `tr('key')`),
  with definite / probable / inconclusive confidence (LOC002, LOC015, LOC016).
- Flutter configuration checks for `pubspec.yaml`, `l10n.yaml`, generated
  output, literal `supportedLocales` and JSON asset declarations (LOC007).
- YAML configuration with validation, ignore rules, severity overrides and an
  `init` command.
- Terminal, JSON (schema version 1) and self-contained HTML reports.
- Stable exit codes: 0 passed, 1 violations, 2 usage/configuration, 3 failure.
