# Contributing to Localization Doctor

Thanks for helping. This document covers local setup, the checks every change
must pass, and how the code is organized.

## Setup

```bash
dart pub get
dart run localization_doctor --path example/sample_app
```

Dart 3.11 or later is required.

## Checks

Every pull request must pass the same checks as CI:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

Never weaken or delete a test to make a build pass. Every bug fix needs a
regression test.

## Architecture

```text
lib/src/
  cli/          argument parsing, commands, exit codes (no audit logic)
  config/       configuration model and validating YAML loader
  discovery/    locale names and translation-file discovery
  parsers/      location-aware JSON parser, ARB/JSON translation parsers, ICU parser
  source/       Dart source scanning with package:analyzer (never executes code)
  flutter/      read-only pubspec.yaml / l10n.yaml reader
  analyzers/    checks that turn parsed data into diagnostics
  models/       Diagnostic, TranslationFile, AuditResult
  reporters/    terminal, JSON and HTML renderers
  auditor.dart  orchestrates discovery, parsing, analysis and policy
```

Analyzers return `Diagnostic` values. Reporters only render an `AuditResult`.
Keep these two layers separate so every format shows the same results.

## Adding a diagnostic

1. Add a value to `DiagnosticCode` with the next free `LOCxxx` id. Never
   renumber or reuse an id.
2. Emit it from an analyzer with an actionable `suggestion`.
3. Map it to a check in `ChecksConfig.isEnabled`.
4. Document it in the README's diagnostic table. A test fails if you forget.
5. Add tests for positive and negative cases.

## Adding a translation format

1. Add the format to `TranslationFormat`.
2. Write a parser that returns `ParsedTranslationFile` with canonical keys and
   source locations.
3. Call it from `LocalizationAuditor._buildBundles`.
4. Add placeholder handling in `PlaceholderAnalyzer` if the format has
   placeholders.

## Releasing (maintainers)

1. Update `version` in `pubspec.yaml`, `lib/src/version.dart` and
   `CHANGELOG.md`. A test checks that they match.
2. Run the checks above, then `dart pub publish --dry-run`.
3. Tag the release `vX.Y.Z` and run `dart pub publish`.

## Code of conduct

Be respectful and constructive. Harassment of any kind is not tolerated.
