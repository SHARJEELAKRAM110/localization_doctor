# Localization Doctor

`localization_doctor` is a command-line tool that audits the translation files
of Flutter and Dart projects before they reach production. It reads ARB and
JSON translations and your Dart sources, then reports missing, unused,
duplicate and inconsistent translations. Reports come as terminal output, JSON
or a self-contained HTML page, and the exit codes are stable enough to gate CI.

It runs offline, never executes your code, never uploads anything and never
modifies your project.

## Problems it solves

- A translation is missing in one language and users see the fallback (or a
  build fails in `gen-l10n`).
- A key was copied twice into a JSON file. `jsonDecode` keeps only the last
  value, so the first one silently disappears.
- A translator renamed `{name}` to `{nom}`, so the placeholder is never
  filled in.
- Old keys pile up because nobody knows whether they are still used.
- `pubspec.yaml`, `l10n.yaml`, `supportedLocales` and the translation files
  no longer agree with each other.

## Features

| Check | Code | Status |
|---|---|---|
| ARB and JSON discovery, locale detection from file names, `@@locale` or explicit mappings | — | Supported |
| Malformed files with line and column | `LOC006` | Supported |
| Duplicate keys at every nesting level, detected before decoding | `LOC003` | Supported |
| Missing keys, extra keys, empty values, invalid value types | `LOC001` `LOC008` `LOC005` `LOC009` | Supported |
| Nested JSON keys (`home.title`) and structure mismatches | `LOC011` | Supported |
| Empty locale files and missing required locales | `LOC012` `LOC013` | Supported |
| ICU message syntax for ARB (plural, select, date, time, `use-escaping`, `relax-syntax`) | `LOC010` | Supported |
| Placeholder consistency for ARB, including `@key.placeholders` metadata | `LOC004` `LOC014` | Supported |
| Placeholder consistency for JSON with a configurable pattern | `LOC004` | Supported |
| Unused keys via generated localizations (`AppLocalizations.of(context)!.key`, variables, fields, parameters, custom accessors) | `LOC002` | Supported (static analysis) |
| Unused keys via JSON lookups (`'key'.tr()`, `tr('key')`, `'key'.tr`) | `LOC002` `LOC015` `LOC016` | Supported (static analysis) |
| Flutter configuration: `generate: true`, dependencies, `l10n.yaml`, generated output, literal `supportedLocales`, JSON asset declarations | `LOC007` | Supported where reliably detectable |
| Locale coverage table | — | Supported |
| Terminal, JSON and HTML reports | — | Supported |
| Other formats (YAML, `.properties`, XLIFF, gettext) | — | Not yet supported |
| Automatic fixes | — | Not supported by design (the audit is read-only) |

## Installation

Global activation keeps the tool's dependencies separate from your app's
dependencies:

```bash
dart pub global activate localization_doctor
```

You can also add it as a development dependency:

```bash
dart pub add --dev localization_doctor
```

Requires Dart 3.11 or later (Flutter 3.41 or later). The Flutter SDK is not
needed to run audits.

## Quick start

From the root of your Flutter project:

```bash
localization_doctor init     # optional: writes localization_doctor.yaml
localization_doctor          # same as `localization_doctor audit`
```

As a development dependency, use `dart run localization_doctor` instead of
`localization_doctor`.

Without a configuration file the tool:

- reads `l10n.yaml` (arb-dir, template file, output class, escaping);
- searches `lib/l10n`, `lib/src/l10n`, `lib/i18n`, `l10n`,
  `assets/translations`, `assets/i18n`, `assets/l10n`, `assets/lang`,
  `assets/langs`, `assets/locales`, `i18n` and `translations`;
- uses the `l10n.yaml` template locale as the base, else `en`, else the first
  locale alphabetically;
- scans `lib/` for key usage.

## Supported localization formats

### ARB (Flutter `gen-l10n`)

- Files such as `app_en.arb` and `app_ur.arb`. The locale comes from the
  file name or from `@@locale`.
- Keys starting with `@@` are global attributes. Keys starting with `@` are
  metadata and are never counted as translations.
- Every message must be a string. Plurals and selects use ICU syntax inside
  the string.
- `use-escaping` and `relax-syntax` are read from `l10n.yaml`. You can
  override them with `localization.arb_use_escaping` and
  `localization.arb_relax_syntax`.

### JSON

- Files such as `en.json`, `app_en.json` and `en-US.json`.
- Nested objects become canonical dotted keys: `{"home": {"title": "…"}}` is
  `home.title`. The separator is configurable (`localization.key_separator`).
- If a flat key containing the separator (`"home.title"`) collides with a
  nested path, it is reported as ambiguous (`LOC011`) and never merged
  silently.
- Values must be strings or objects. `null`, numbers, booleans and arrays are
  reported (`LOC009`).
- Placeholders default to `{name}`. Set
  `localization.json_placeholder_pattern` to a regular expression whose
  group 1 is the name, for example `'\{\{(\w+)\}\}'` for `{{name}}`. A match
  with an empty group 1 counts as a positional placeholder, for example
  `'\{(\w*)\}'` for easy_localization's `{}`. Matches preceded by a backslash
  are literal.

### Locale detection

Detection runs in this order:

1. `localization.locale_mappings`
2. the file name, where the locale is the last segment after `_` or `-`:
   `app_en`, `app_en_US`, `intl_zh_Hant_TW`, `en`, `en-US`
3. ARB `@@locale`

Files in a bundle are grouped by directory, prefix and format. For example,
`lib/l10n/app_*.arb` and `lib/l10n/intl_*.arb` are separate bundles, each with
its own base locale. Files whose locale cannot be determined are listed under
"skipped files" in verbose and JSON output.

## CLI reference

```text
localization_doctor [audit] [options]
localization_doctor init [--path <dir>]
localization_doctor --help | --version
```

Running without a command is the same as running `audit`.

| Option | Description |
|---|---|
| `-p, --path <dir>` | Project directory. Default: `.` |
| `-c, --config <file>` | Configuration file. Default: `<path>/localization_doctor.yaml` if present. A missing explicit file is an error. |
| `-b, --base-locale <locale>` | Reference locale. Overrides `base_locale`. |
| `-f, --format <list>` | `terminal`, `json`, `html`. Repeat or comma-separate. |
| `-o, --output-dir <dir>` | Where json/html files are written. Default: `<path>/build/localization_doctor`. |
| `--strict` | Fail on warnings as well as errors. |
| `-v, --verbose` | Show related locations, scanned file count and skipped files. |
| `-q, --quiet` | Print only the summary and status. Cannot be combined with `--verbose`. |
| `--[no-]color` | Force colors on or off. By default colors are used only on ANSI terminals and only when `NO_COLOR` is unset. |
| `-h, --help` | Usage. |
| `--version` | Print the version. |

**Output routing.** A single `json` or `html` format (with no output directory
set) goes to standard output, and nothing else is printed there. In every
other case the terminal report goes to stdout and json/html reports are
written to `localization_doctor_report.json` / `.html` in the output
directory. A "Report written to …" line goes to stderr.

**Precedence.** Command-line flags override the configuration file, which
overrides values read from `l10n.yaml` and `pubspec.yaml`, which override
built-in defaults.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Audit completed with no diagnostics at or above the failure threshold. |
| `1` | Audit completed with policy violations. Malformed translation files are reported here, as `LOC006` errors. |
| `2` | Invalid arguments or configuration (unknown option, bad YAML, unknown config key, invalid locale or regex, `init` target already exists). |
| `3` | The audit could not run (project directory missing, report could not be written, internal error). |

The failure threshold is `error` by default. `fail_on: warning` or `--strict`
lowers it to `warning`. Info diagnostics never fail an audit unless
`fail_on: info` is set.

## Configuration reference

Create `localization_doctor.yaml` in the project root (`localization_doctor
init` writes a commented starter). Every key is optional. Unknown keys are
rejected, with a suggestion when one is close.

```yaml
base_locale: en                 # default: l10n.yaml template, else en, else first
fail_on: error                  # error | warning | info

localization:
  directories: [lib/l10n, assets/translations]   # default: auto-detect
  formats: [arb, json]          # default: both
  required_locales: [en, ur, fr] # must have a file and be complete
  optional_locales: [de]        # may be incomplete (see below)
  fail_on_optional_locales: false
  locale_mappings:              # explicit file -> locale
    assets/translations/english.json: en
  key_separator: "."            # JSON nesting separator
  json_placeholder_pattern: '\{([A-Za-z_][A-Za-z0-9_]*)\}'
  arb_use_escaping: false       # default: from l10n.yaml
  arb_relax_syntax: false       # default: from l10n.yaml

source:
  directories: [lib]
  exclude: [lib/legacy/**]      # globs relative to the project root
  localization_classes: [AppLocalizations]   # default: l10n.yaml output-class
  accessors: [context.l10n]     # expressions that return the localizations object
  json_lookup_functions: [tr, plural, translate]

checks:                          # all default to true
  missing_keys: true             # LOC001, LOC013
  extra_keys: true               # LOC008
  unused_keys: true              # LOC002, LOC015, LOC016
  duplicate_keys: true           # LOC003
  placeholder_mismatches: true   # LOC004
  empty_values: true             # LOC005, LOC012
  message_syntax: true           # LOC010
  configuration: true            # LOC007

ignore:
  keys: [debug.*]                # removed from all key checks and from coverage
  unused_keys: [errors.*]        # never reported as unused
  diagnostics:                   # known exceptions; every field set must match
    - code: LOC008
      locale: fr
      key: legacy.*
      path: lib/l10n/app_fr.arb  # glob

severity:                        # per-code severity overrides
  LOC008: error

reports:
  formats: [terminal, json]
  output_directory: build/localization_doctor
```

Directories and paths must stay inside the project. All paths use forward
slashes on every platform.

### Optional locales

For locales in `optional_locales`, missing keys (`LOC001`) and all warnings
are downgraded to info, so they never fail a strict audit. Errors that break
parsing or code generation, such as `LOC003`, `LOC004` (unexpected
placeholder), `LOC006` and `LOC010`, keep their severity. Set
`fail_on_optional_locales: true` to treat optional locales like required ones.

### Ignore rules

- Key patterns match the canonical key exactly. `*` matches any characters,
  including the separator. `?` matches a single character.
- `ignore.keys` removes keys from coverage totals and suppresses every
  key-level diagnostic for them, except duplicate keys (`LOC003`).
- `ignore.unused_keys` only affects unused-key analysis.
- `ignore.diagnostics` suppresses matching diagnostics.
- `LOC006` (invalid translation file) can never be ignored or downgraded.
  Invalid configuration always stops the run with exit code 2.
- Suppressed diagnostics are counted in the summary (`N suppressed`) and in
  JSON `summary.suppressed`.

### Coverage rules

`Total` is the number of non-ignored message keys in the base locale. ARB
`@` metadata is never counted. A key is **translated** only when it is
present with a non-empty string. Empty or whitespace-only values are counted
in `Empty`, values of the wrong type in `Invalid`, and absent keys in
`Missing`. None of these count as translated. Coverage is
`translated / total`, rounded to one decimal place. When a locale file cannot
be parsed, all its keys count as missing and the row is marked
`(invalid file)`.

## Diagnostic codes

Codes are stable and never reused.

| Code | Title | Default severity |
|---|---|---|
| `LOC001` | Missing translation key | error (info for optional locales) |
| `LOC002` | Unused translation key | warning when definite, info when probable or inconclusive |
| `LOC003` | Duplicate translation key | error |
| `LOC004` | Placeholder mismatch | error for unexpected placeholders and argument-kind changes; warning for missing placeholders and metadata differences |
| `LOC005` | Empty translation value | warning |
| `LOC006` | Invalid translation file (malformed JSON, wrong root type, unreadable, not UTF-8) | error, cannot be suppressed |
| `LOC007` | Localization configuration issue | error, warning or info depending on the problem |
| `LOC008` | Key not present in base locale | warning |
| `LOC009` | Invalid translation value type | error |
| `LOC010` | ICU message syntax error | error (warning for a plural or select without `other`) |
| `LOC011` | Inconsistent key structure (nested vs. flat, ambiguous dotted keys) | error |
| `LOC012` | Locale file contains no translations | warning |
| `LOC013` | Missing locale file (required locale, or base locale missing from a bundle) | error |
| `LOC014` | ARB metadata issue (`@key` without a message, `@@locale` mismatch, malformed metadata) | warning |
| `LOC015` | Dynamic key usage limits unused-key analysis | info |
| `LOC016` | Key referenced in source but not defined in the base JSON | warning (probable) |

Every diagnostic has a **confidence** value:

- `definite`: observed directly in the files.
- `probable`: likely, but static analysis cannot rule out other usage.
- `inconclusive`: there is evidence both ways, so review it manually.

### How unused keys are classified

**Generated localizations (ARB).**

- A key is used when its getter or method is accessed on one of:
  - `AppLocalizations.of(context)` with `!`, `?.` or nothing;
  - `lookupAppLocalizations(locale)`;
  - a variable, field or parameter that holds it or is typed as it;
  - an accessor configured in `source.accessors`.
- If no such access exists but an identifier with the key's name appears
  elsewhere, the result is `inconclusive`.
- If the name appears nowhere in the scanned sources, the result is
  `definite`.
- If the whole project contains no recognizable access at all, results are
  only `probable`, and a hint suggests configuring `source.accessors`.

**JSON lookups.**

- A key is used when a string literal is passed to a lookup function
  (`'key'.tr()`, `tr('key')`, `context.tr('key')`, `plural('key', n)`,
  `'key'.tr`).
- Keys that match the literal prefix of an interpolated lookup
  (`'errors.$code'.tr()`), or that appear as any other string literal, are
  `inconclusive`.
- When some lookups use keys that cannot be determined statically, the
  remaining keys are `probable`.

Generated localization files, `*.g.dart`, `*.freezed.dart`, `**/generated/**`,
`build/`, `.dart_tool/` and hidden directories are never scanned. Source files
are parsed with `package:analyzer` and are never executed.

## Sample terminal output

Real output from `localization_doctor --path example/sample_app`:

```text
Localization Doctor 0.1.0
Project: /path/to/localization_doctor/example/sample_app

Translation bundles
  lib/l10n/app_*.arb  base: en  locales: en, fr, ur

Locale coverage
  Bundle              Locale     Total  Translated  Missing  Empty  Invalid  Coverage
  lib/l10n/app_*.arb  en (base)      7           7        0      0        0      100%
  lib/l10n/app_*.arb  fr             7           6        0      1        0     85.7%
  lib/l10n/app_*.arb  ur             7           6        1      0        0     85.7%

Diagnostics
  error   LOC001  lib/l10n/app_ur.arb
    Key "settingsTitle" exists in en but is missing from ur.
    fix: Add "settingsTitle" to app_ur.arb.
  error   LOC004  lib/l10n/app_fr.arb:5:3
    "greeting" in fr uses {nom}, which is not defined by the base locale en.
    fix: Use only the placeholders of the base message: {name}.
  warning LOC002  lib/l10n/app_en.arb:28:3
    Key "legacyBanner" appears to be unused: its getter is never referenced in the scanned sources.
    fix: Remove "legacyBanner" from every locale, or add it to "ignore.unused_keys" if it is used dynamically.
  warning LOC004  lib/l10n/app_fr.arb:5:3
    "greeting" in fr does not use {name} from the base locale en.
    fix: Include {name} in the translation, unless omitting it is intentional.
  warning LOC005  lib/l10n/app_fr.arb:8:3
    Translation "logout" is empty in fr.
    fix: Provide a translation for "logout".
  info    LOC007  l10n.yaml  [probable]
    Generated localizations file "lib/l10n/app_localizations.dart" was not found. It is created by `flutter gen-l10n` (or automatically by `flutter pub get`).
    fix: Run `flutter gen-l10n` if the generated code is expected to be checked in.

Summary: 2 errors, 3 warnings, 1 info
FAILED: 2 violations at or above "error" severity
```

## JSON report

`--format json` prints a document with `schemaVersion: 1`. Full sample:
[`doc/sample_report.json`](doc/sample_report.json).

```json
{
  "schemaVersion": 1,
  "tool": { "name": "localization_doctor", "version": "0.1.0" },
  "projectPath": "/path/to/localization_doctor/example/sample_app",
  "generatedAt": "2026-10-26T07:17:01.018398Z",
  "status": "failed",
  "failOn": "error",
  "summary": {
    "errors": 2, "warnings": 3, "infos": 1,
    "violations": 2, "suppressed": 0, "scannedSourceFiles": 1
  },
  "bundles": [
    { "id": "lib/l10n/app_*.arb", "format": "arb", "baseLocale": "en",
      "locales": ["en", "fr", "ur"], "files": ["lib/l10n/app_en.arb", "…"] }
  ],
  "coverage": [
    { "bundle": "lib/l10n/app_*.arb", "locale": "ur", "isBase": false,
      "isOptional": false, "total": 7, "translated": 6, "missing": 1,
      "empty": 0, "invalid": 0, "fileValid": true, "coverage": 85.7 }
  ],
  "diagnostics": [
    {
      "code": "LOC001",
      "title": "Missing translation key",
      "severity": "error",
      "confidence": "definite",
      "message": "Key \"settingsTitle\" exists in en but is missing from ur.",
      "bundle": "lib/l10n/app_*.arb",
      "locale": "ur",
      "key": "settingsTitle",
      "location": { "path": "lib/l10n/app_ur.arb", "line": null, "column": null },
      "relatedLocations": [ { "path": "lib/l10n/app_en.arb", "line": 26, "column": 3 } ],
      "suggestion": "Add \"settingsTitle\" to app_ur.arb."
    }
  ],
  "skippedFiles": []
}
```

Schema notes:

- `status` is `passed` or `failed`.
- `severity` is `error`, `warning` or `info`.
- `confidence` is `definite`, `probable` or `inconclusive`.
- Paths are relative to the project and use forward slashes.
- `line` and `column` are 1-based, or `null` when not applicable.
- Diagnostics are sorted by severity, code, bundle, location, locale and key.
- `generatedAt` is the only field that changes between identical runs.

## HTML report

```bash
localization_doctor --format html > l10n-report.html
# or, together with terminal output:
localization_doctor --format terminal,html --output-dir build/l10n
```

The page is a single file with inline CSS and JavaScript. It loads no
external fonts, scripts or images, so it works offline. It shows:

- the overall status and severity counts;
- locale coverage bars;
- every diagnostic, with search, severity and check filters.

It supports light and dark mode and adapts to narrow screens. All
project-derived text is HTML-escaped. A sample generated from the example
project is in [`doc/sample_report.html`](doc/sample_report.html).

## CI/CD integration

The audit needs only the Dart SDK: no Flutter SDK, build or emulator. Use
`--strict` if warnings should fail the build too.

### GitHub Actions

```yaml
name: Localization audit

on:
  pull_request:
  push:
    branches: [main]

jobs:
  l10n:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
        with:
          sdk: 3.11.4
      - name: Install localization_doctor
        run: dart pub global activate localization_doctor 0.1.0
      - name: Audit translations
        run: >
          dart pub global run localization_doctor audit --strict
          --format terminal,json,html --output-dir l10n-report
      - name: Upload report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: localization-report
          path: l10n-report/
```

The audit step fails the job with exit code 1 when violations are found. The
report is still uploaded because of `if: always()`. To update, change the
version passed to `dart pub global activate` and the `sdk` input. For
stricter supply-chain hygiene, pin each `uses:` action to a full commit SHA.

## Programmatic use

```dart
import 'package:localization_doctor/localization_doctor.dart';

void main() {
  final config = loadConfig('.');
  final result = LocalizationAuditor(projectPath: '.', config: config).run();
  print(const JsonReporter().render(result));
  if (!result.passed) print('${result.violations.length} violations');
}
```

The public API consists of `LocalizationAuditor`, `loadConfig` /
`parseConfig`, `DoctorConfig`, `AuditResult`, `Diagnostic` and the three
reporters. Everything under `lib/src` is internal.

## Known limitations

- Unused-key analysis is static. It cannot see keys built at runtime,
  reflection, or code outside `source.directories`. Results are labelled with
  a confidence instead of claiming certainty.
- Localization objects are tracked by name within a single file, without
  type resolution. An object passed through untyped variables or across files
  is only found through the "identifier appears elsewhere" heuristic
  (`inconclusive`). Configure `source.accessors` for extension getters.
- Only `supportedLocales` lists written as literal `Locale(...)` values are
  compared. `AppLocalizations.supportedLocales` is generated correctly by
  Flutter and needs no check.
- Generated output is checked only when `l10n.yaml` exists. Staleness is
  detected by missing per-language files (definite) and by modification times
  (probable).
- JSON asset declarations are checked only for bundles under `assets/`.
- The ICU parser follows Flutter `gen-l10n`'s grammar (plural, select, date,
  time). Other ICU argument types are reported as syntax errors, as gen-l10n
  does.
- Locale detection from file names requires canonical casing after a prefix
  (`app_en_US`, not `app_en_us`). Use `locale_mappings` for unusual names.
  A whole-name locale with more than one part needs a two-letter language
  (`en_US.json`, but `fil_PH.json` needs a prefix or a mapping).
- Symbolic links are never followed.
- Requires Dart 3.11 or later because it depends on `package:analyzer` 14.x.

## Troubleshooting

**"No translation files were found"**: set `localization.directories`, or
run `localization_doctor init` and edit the generated file.

**Every ARB key is reported as unused (probable)**: your code probably
reaches the localizations object through an extension such as
`context.l10n`. Add it under `source.accessors`. If you renamed the class,
check `output-class` in `l10n.yaml` or `source.localization_classes`.

**Keys used through string building are reported as unused**: add them, or a
pattern such as `errors.*`, to `ignore.unused_keys`.

**Files are listed as skipped**: the locale could not be read from the file
name. Add an entry to `localization.locale_mappings` or, for ARB files, add
`@@locale`.

**Dependency conflicts after `dart pub add --dev`**: your app pins a
different `analyzer` version. Use `dart pub global activate` instead.

**Colors in CI logs**: colors are disabled automatically when stdout is not a
terminal. Set `NO_COLOR=1` or pass `--no-color` to be explicit.

**Exit code 2**: the message on stderr includes the configuration file, line
and column of the problem.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to
set up, run the checks and add a new diagnostic. Please open an issue before
starting large changes.

## License

MIT. See [LICENSE](LICENSE).
