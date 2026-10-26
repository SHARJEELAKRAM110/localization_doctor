import 'package:localization_doctor/localization_doctor.dart';
import 'package:test/test.dart';

import '../support/test_project.dart';

const enArb = '''
{
  "@@locale": "en",
  "title": "Title",
  "greeting": "Hello {name}",
  "@greeting": {"placeholders": {"name": {"type": "String"}}},
  "items": "{count, plural, =1{one item} other{{count} items}}",
  "@items": {"placeholders": {"count": {"type": "int"}}}
}
''';

const mainUsingAll = '''
void f(context) {
  final l10n = AppLocalizations.of(context)!;
  l10n.title;
  l10n.greeting('a');
  l10n.items(2);
}
''';

void main() {
  group('missing and extra keys', () {
    test('a complete project passes', () {
      final project = TestProject.create(
        flutterProject(
          arb: {
            'app_en.arb': enArb,
            'app_ur.arb':
                '{"title": "عنوان", "greeting": "سلام {name}", '
                '"items": "{count, plural, other{{count} آئٹمز}}"}',
          },
          main: mainUsingAll,
        ),
      );
      final result = project.audit();
      expect(
        result.diagnostics.where((d) => d.severity != Severity.info),
        isEmpty,
      );
      expect(result.passed, isTrue);
      expect(result.coverage.map((c) => (c.locale, c.percent)), [
        ('en', 100.0),
        ('ur', 100.0),
      ]);
    });

    test('reports missing keys per locale with base location', () {
      final project = TestProject.create(
        flutterProject(
          arb: {'app_en.arb': enArb, 'app_fr.arb': '{"title": "Titre"}'},
          main: mainUsingAll,
        ),
      );
      final missing = withCode(project.audit(), DiagnosticCode.missingKey);
      expect(missing.map((d) => d.key), ['greeting', 'items']);
      expect(missing.first.locale, 'fr');
      expect(missing.first.severity, Severity.error);
      expect(missing.first.location!.path, 'lib/l10n/app_fr.arb');
      expect(missing.first.relatedLocations.single.path, 'lib/l10n/app_en.arb');
    });

    test('reports keys that exist only in a target locale', () {
      final project = TestProject.create(
        flutterProject(
          arb: {
            'app_en.arb': '{"title": "Title"}',
            'app_fr.arb': '{"title": "Titre", "bonus": "Bonus"}',
          },
          main: 'f(c) => AppLocalizations.of(c)!.title;',
        ),
      );
      final extra = withCode(project.audit(), DiagnosticCode.extraKey).single;
      expect(extra.key, 'bonus');
      expect(extra.severity, Severity.warning);
      expect(extra.location!.line, 1);
    });

    test('empty values and empty files are reported', () {
      final project = TestProject.create(
        flutterProject(
          arb: {
            'app_en.arb': '{"title": "Title", "body": "  "}',
            'app_fr.arb': '{"title": "", "body": "Corps"}',
            'app_ur.arb': '{"@@locale": "ur"}',
          },
          main: 'f(c) { final l = AppLocalizations.of(c)!; l.title; l.body; }',
        ),
      );
      final result = project.audit();
      final empty = withCode(result, DiagnosticCode.emptyValue);
      expect(empty.map((d) => '${d.locale}:${d.key}'), ['en:body', 'fr:title']);
      expect(
        withCode(result, DiagnosticCode.emptyLocaleFile).single.locale,
        'ur',
      );
      final fr = result.coverage.firstWhere((c) => c.locale == 'fr');
      expect((fr.total, fr.translated, fr.empty, fr.missing), (2, 1, 1, 0));
      expect(fr.percent, 50);
    });

    test('required locales without files are errors', () {
      final project = TestProject.create(
        flutterProject(arb: {'app_en.arb': '{"title": "T"}'}),
      );
      final result = project.auditYaml(
        'localization:\n  required_locales: [en, ur, fr]',
      );
      final missing = withCode(result, DiagnosticCode.missingLocale);
      expect(missing.map((d) => d.locale), ['fr', 'ur']);
      expect(missing.first.suggestion, contains('lib/l10n/app_fr.arb'));
    });

    test('nested structure mismatch is reported once, not as missing keys', () {
      final project = TestProject.create({
        'assets/translations/en.json':
            '{"errors": {"a": "A", "b": "B"}, "ok": "OK"}',
        'assets/translations/fr.json': '{"errors": "Erreur", "ok": "OK"}',
      });
      final result = project.auditYaml('checks:\n  unused_keys: false');
      final mismatch = withCode(
        result,
        DiagnosticCode.structureMismatch,
      ).single;
      expect(mismatch.key, 'errors');
      expect(withCode(result, DiagnosticCode.missingKey), isEmpty);
      expect(withCode(result, DiagnosticCode.extraKey), isEmpty);
      final fr = result.coverage.firstWhere((c) => c.locale == 'fr');
      expect(fr.missing, 2);
    });

    test('invalid value types do not count as translated', () {
      final project = TestProject.create({
        'assets/translations/en.json': '{"a": "A", "b": "B"}',
        'assets/translations/fr.json': '{"a": 1, "b": "B"}',
      });
      final result = project.auditYaml('checks:\n  unused_keys: false');
      expect(withCode(result, DiagnosticCode.invalidValueType).single.key, 'a');
      final fr = result.coverage.firstWhere((c) => c.locale == 'fr');
      expect((fr.translated, fr.invalid), (1, 1));
    });
  });

  group('duplicates and malformed files', () {
    test('a malformed file does not stop the audit of other files', () {
      final project = TestProject.create({
        'assets/translations/en.json': '{"a": "A", "b": "B"}',
        'assets/translations/fr.json': '{"a": "A"}',
        'assets/translations/ur.json': '{"a": "A" "b": "B"}',
      });
      final result = project.auditYaml('checks:\n  unused_keys: false');
      final invalid = withCode(result, DiagnosticCode.invalidFile).single;
      expect(invalid.location!.path, 'assets/translations/ur.json');
      expect(invalid.location!.line, 1);
      expect(invalid.location!.column, 11);
      expect(withCode(result, DiagnosticCode.missingKey).single.locale, 'fr');
      final ur = result.coverage.firstWhere((c) => c.locale == 'ur');
      expect(ur.fileValid, isFalse);
    });

    test('duplicate keys are errors and survive key ignores', () {
      final project = TestProject.create({
        'assets/translations/en.json': '{"a": "1", "a": "2"}',
      });
      final result = project.auditYaml(
        'ignore:\n  keys: [a]\nchecks:\n  unused_keys: false',
      );
      expect(withCode(result, DiagnosticCode.duplicateKey).single.key, 'a');
      expect(result.passed, isFalse);
    });

    test('ARB @@locale is used when the file name has no locale', () {
      final project = TestProject.create({
        'lib/l10n/english.arb': '{"@@locale": "en", "a": "A"}',
        'lib/l10n/french.arb': '{"@@locale": "fr"}',
        'lib/l10n/unknown.arb': '{"a": "A"}',
      });
      final result = project.auditYaml('checks:\n  unused_keys: false');
      expect(result.bundles.single.locales, ['en', 'fr']);
      expect(result.skippedFiles.single, startsWith('lib/l10n/unknown.arb'));
    });

    test('@@locale that disagrees with the file name is reported', () {
      final project = TestProject.create({
        'lib/l10n/app_en.arb': '{"@@locale": "en", "a": "A"}',
        'lib/l10n/app_fr.arb': '{"@@locale": "de", "a": "A"}',
      });
      final result = project.auditYaml('checks:\n  unused_keys: false');
      final meta = withCode(result, DiagnosticCode.arbMetadata).single;
      expect(meta.message, contains('"de"'));
    });
  });

  group('placeholders', () {
    AuditResult auditArb(String fr, {String en = enArb, String extra = ''}) {
      final project = TestProject.create(
        flutterProject(
          arb: {'app_en.arb': en, 'app_fr.arb': fr},
          main: mainUsingAll,
        ),
      );
      return project.auditYaml('checks:\n  unused_keys: false\n$extra');
    }

    test('unexpected placeholder is an error, missing is a warning', () {
      final result = auditArb(
        '{"title": "T", "greeting": "Bonjour {nom}", '
        '"items": "{count, plural, other{{count}}}"}',
      );
      final diags = withCode(
        result,
        DiagnosticCode.placeholderMismatch,
      ).toList();
      expect(diags.map((d) => d.severity), [Severity.error, Severity.warning]);
      expect(diags.first.message, contains('{nom}'));
      expect(diags.last.message, contains('{name}'));
    });

    test('syntax errors are reported separately from mismatches', () {
      final result = auditArb(
        '{"title": "T", "greeting": "Bonjour {name", '
        '"items": "{count, plural, other{{count}}}"}',
      );
      expect(
        withCode(result, DiagnosticCode.messageSyntax).single.key,
        'greeting',
      );
      expect(withCode(result, DiagnosticCode.placeholderMismatch), isEmpty);
    });

    test('plural vs select argument kinds must match', () {
      final result = auditArb(
        '{"title": "T", "greeting": "{name}", '
        '"items": "{count, select, other{x {count}}}"}',
      );
      final d = withCode(result, DiagnosticCode.placeholderMismatch).single;
      expect(d.message, contains('plural'));
      expect(d.message, contains('select'));
    });

    test('base metadata must match the base message', () {
      final result = auditArb(
        '{"title": "T {extra}", "greeting": "{name}", '
        '"items": "{count, plural, other{{count}}}"}',
        en: '''
{
  "title": "Title {who}",
  "@title": {"placeholders": {"other": {}}},
  "greeting": "Hello {name}",
  "items": "{count, plural, other{{count}}}"
}''',
      );
      final messages = withCode(
        result,
        DiagnosticCode.placeholderMismatch,
      ).map((d) => d.message).toList();
      expect(messages, hasLength(4));
      expect(messages.any((m) => m.contains('does not declare it')), isTrue);
      expect(messages.any((m) => m.contains('never uses it')), isTrue);
      expect(messages.any((m) => m.contains('{extra}')), isTrue);
      expect(messages.any((m) => m.contains('does not use {who}')), isTrue);
    });

    test('differing placeholder metadata in a target file is a warning', () {
      final result = auditArb('''
{
  "title": "T", "greeting": "{name}",
  "@greeting": {"placeholders": {"name": {"type": "int"}}},
  "items": "{count, plural, other{{count}}}"
}''');
      final d = withCode(result, DiagnosticCode.placeholderMismatch).single;
      expect(d.severity, Severity.warning);
      expect(d.message, contains('String in en but int in fr'));
    });

    test('use-escaping from l10n.yaml makes quoted braces literal', () {
      final project = TestProject.create(
        flutterProject(
          arb: {
            'app_en.arb': '{"a": "Use \'{braces}\' here"}',
            'app_fr.arb': '{"a": "Utilisez \'{accolades}\' ici"}',
          },
          l10nYaml: 'use-escaping: true\n',
          main: 'f(c) => AppLocalizations.of(c)!.a;',
        ),
      );
      final result = project.audit();
      expect(withCode(result, DiagnosticCode.messageSyntax), isEmpty);
      expect(withCode(result, DiagnosticCode.placeholderMismatch), isEmpty);
    });

    test('JSON placeholders use the configured pattern', () {
      final project = TestProject.create({
        'assets/translations/en.json': '{"a": "Hi {{user}} {{n}}", "b": "{x}"}',
        'assets/translations/fr.json':
            '{"a": "Salut {{utilisateur}} {{n}}", "b": "{y}"}',
      });
      final result = project.auditYaml(r'''
checks:
  unused_keys: false
localization:
  json_placeholder_pattern: '\{\{(\w+)\}\}'
''');
      final diags = withCode(
        result,
        DiagnosticCode.placeholderMismatch,
      ).toList();
      expect(diags.map((d) => d.key).toSet(), {'a'});
      expect(diags.first.message, contains('{utilisateur}'));
    });

    test('JSON positional placeholder counts are compared', () {
      final project = TestProject.create({
        'assets/translations/en.json': '{"a": "{} of {}"}',
        'assets/translations/fr.json': '{"a": "{}"}',
      });
      final result = project.auditYaml(r'''
checks:
  unused_keys: false
localization:
  json_placeholder_pattern: '\{(\w*)\}'
''');
      final d = withCode(result, DiagnosticCode.placeholderMismatch).single;
      expect(d.message, contains('1 positional placeholder(s) in fr but 2'));
    });
  });

  group('unused keys', () {
    test('ARB getter that is never referenced is a definite warning', () {
      final project = TestProject.create(
        flutterProject(
          arb: {'app_en.arb': '{"used": "U", "unused": "X", "shadow": "S"}'},
          main: '''
void f(c, other) {
  AppLocalizations.of(c)!.used;
  other.shadow;
}
''',
        ),
      );
      final unused = withCode(
        project.audit(),
        DiagnosticCode.unusedKey,
      ).toList();
      expect(unused.map((d) => (d.key, d.confidence, d.severity)), [
        ('unused', Confidence.definite, Severity.warning),
        ('shadow', Confidence.inconclusive, Severity.info),
      ]);
    });

    test('without any recognized access, unused keys are only probable', () {
      final project = TestProject.create(
        flutterProject(
          arb: {'app_en.arb': '{"title": "T"}'},
          main: 'void f(c) => c.l10n.title2;',
        ),
      );
      final result = project.audit();
      final unused = withCode(result, DiagnosticCode.unusedKey).single;
      expect(unused.confidence, Confidence.probable);
      expect(unused.severity, Severity.info);
      expect(
        withCode(
          result,
          DiagnosticCode.configuration,
        ).any((d) => d.message.contains('No access through AppLocalizations')),
        isTrue,
      );
    });

    test('configured accessor makes keys used', () {
      final project = TestProject.create(
        flutterProject(
          arb: {'app_en.arb': '{"title": "T"}'},
          main: 'void f(c) => c.l10n.title;',
        ),
      );
      final result = project.auditYaml('source:\n  accessors: [c.l10n]');
      expect(withCode(result, DiagnosticCode.unusedKey), isEmpty);
    });

    test('generated localization files do not make keys look used', () {
      final project = TestProject.create(
        flutterProject(
          arb: {'app_en.arb': '{"used": "U", "unused": "X"}'},
          main: 'void f(c) => AppLocalizations.of(c)!.used;',
        )..addAll({
          'lib/l10n/app_localizations.dart':
              'abstract class AppLocalizations { String get unused; }',
          'lib/l10n/app_localizations_en.dart':
              'class AppLocalizationsEn extends AppLocalizations {'
              ' String get unused => "X"; }',
        }),
      );
      final unused = withCode(project.audit(), DiagnosticCode.unusedKey).single;
      expect(unused.key, 'unused');
      expect(unused.confidence, Confidence.definite);
    });

    test('JSON keys: literal, dynamic prefix, string literal and unknown', () {
      final project = TestProject.create({
        'assets/translations/en.json': '''
{
  "home": {"title": "Home"},
  "errors": {"network": "N"},
  "menu": {"open": "Open"},
  "never": "Never"
}''',
        'lib/main.dart': r'''
const menuKeys = ['menu.open'];
void f(String code) {
  'home.title'.tr();
  'errors.$code'.tr();
  'home.missing'.tr();
}
''',
      });
      final result = project.audit();
      final unused = {
        for (final d in withCode(result, DiagnosticCode.unusedKey))
          d.key: d.confidence,
      };
      expect(unused, {
        'errors.network': Confidence.inconclusive,
        'menu.open': Confidence.inconclusive,
        'never': Confidence.definite,
      });
      expect(
        withCode(result, DiagnosticCode.undefinedKey).single.key,
        'home.missing',
      );
      expect(
        withCode(result, DiagnosticCode.dynamicKeyUsage).single.location!.line,
        4,
      );
    });

    test('easy_localization LocaleKeys constants count as usage', () {
      final project = TestProject.create({
        'pubspec.yaml': 'name: x\n',
        'assets/translations/en.json':
            '{"home": {"title": "Home"}, "Add": "Add", "never": "Never"}',
        'assets/translations/fr.json':
            '{"home": {"title": "Accueil"}, "Add": "Ajouter", "never": "Jamais"}',
        'lib/translations/locale_keys.g.dart': '''
abstract class LocaleKeys {
  static const home_title = 'home.title';
  static const Add = 'Add';
  static const never = 'never';
  static const removed = 'removed';
}
''',
        'lib/main.dart': '''
void f() {
  tr(LocaleKeys.home_title);
  LocaleKeys.Add.tr();
  LocaleKeys.removed.tr();
}
''',
      });
      final result = project.audit();
      final unused = withCode(result, DiagnosticCode.unusedKey).single;
      expect((unused.key, unused.confidence), ('never', Confidence.definite));
      expect(withCode(result, DiagnosticCode.dynamicKeyUsage), isEmpty);
      final undefined = withCode(result, DiagnosticCode.undefinedKey).single;
      expect(undefined.key, 'removed');
      expect(undefined.location!.path, 'lib/main.dart');
    });

    test('a lookup with an unknown key downgrades unused JSON keys', () {
      final project = TestProject.create({
        'assets/translations/en.json': '{"a": "A"}',
        'lib/main.dart': 'void f(String k) => tr(k);',
      });
      final unused = withCode(project.audit(), DiagnosticCode.unusedKey).single;
      expect(unused.confidence, Confidence.probable);
      expect(unused.severity, Severity.info);
    });

    test('ignore.unused_keys hides only unused-key results', () {
      final project = TestProject.create({
        'assets/translations/en.json': '{"dyn": {"a": "", "b": "B"}}',
        'lib/main.dart': 'void f() {}',
      });
      final result = project.auditYaml('ignore:\n  unused_keys: [dyn.*]');
      expect(withCode(result, DiagnosticCode.unusedKey), isEmpty);
      expect(withCode(result, DiagnosticCode.emptyValue).single.key, 'dyn.a');
    });

    test('no scanned sources skips the check with an explanation', () {
      final project = TestProject.create({
        'assets/translations/en.json': '{"a": "A"}',
      });
      final result = project.audit();
      expect(withCode(result, DiagnosticCode.unusedKey), isEmpty);
      expect(
        withCode(
          result,
          DiagnosticCode.configuration,
        ).any((d) => d.message.contains('No Dart source files')),
        isTrue,
      );
    });
  });

  group('policy', () {
    TestProject warningOnly() => TestProject.create({
      'assets/translations/en.json': '{"a": "A"}',
      'assets/translations/fr.json': '{"a": "A", "extra": "E"}',
      'lib/main.dart': "f() => 'a'.tr();",
    });

    test('warnings pass by default and fail in strict mode', () {
      final project = warningOnly();
      expect(project.audit().passed, isTrue);
      expect(project.auditYaml('fail_on: warning').passed, isFalse);
    });

    test('severity overrides apply', () {
      final result = warningOnly().auditYaml('severity:\n  LOC008: error');
      expect(
        withCode(result, DiagnosticCode.extraKey).single.severity,
        Severity.error,
      );
      expect(result.passed, isFalse);
    });

    test('disabled checks produce no diagnostics', () {
      final result = warningOnly().auditYaml('checks:\n  extra_keys: false');
      expect(withCode(result, DiagnosticCode.extraKey), isEmpty);
    });

    test('ignore rules suppress matching diagnostics and are counted', () {
      final result = warningOnly().auditYaml('''
ignore:
  diagnostics:
    - code: LOC008
      locale: fr
      key: ext*
''');
      expect(withCode(result, DiagnosticCode.extraKey), isEmpty);
      expect(result.suppressedCount, 1);
    });

    test('ignore rule with a non-matching locale has no effect', () {
      final result = warningOnly().auditYaml('''
ignore:
  diagnostics:
    - code: LOC008
      locale: ur
''');
      expect(withCode(result, DiagnosticCode.extraKey), hasLength(1));
    });

    test('ignore.keys removes keys from checks and coverage', () {
      final project = TestProject.create({
        'assets/translations/en.json': '{"a": "A", "debug": {"x": "X"}}',
        'assets/translations/fr.json': '{"a": "A"}',
        'lib/main.dart': "f() => 'a'.tr();",
      });
      final result = project.auditYaml('ignore:\n  keys: [debug.*]');
      expect(withCode(result, DiagnosticCode.missingKey), isEmpty);
      expect(result.coverage.first.total, 1);
    });

    test('optional locales do not fail strict audits by default', () {
      final project = TestProject.create({
        'pubspec.yaml': 'name: x\n',
        'assets/translations/en.json': '{"a": "A", "b": "B"}',
        'assets/translations/de.json': '{"a": "", "extra": "x"}',
        'lib/main.dart': "f() { 'a'.tr(); 'b'.tr(); }",
      });
      final lenient = project.auditYaml('''
fail_on: warning
localization:
  optional_locales: [de]
''');
      expect(lenient.passed, isTrue);
      expect(
        lenient.diagnostics
            .where((d) => d.locale == 'de')
            .map((d) => d.severity),
        everyElement(Severity.info),
      );
      expect(
        lenient.coverage.firstWhere((c) => c.locale == 'de').isOptional,
        isTrue,
      );

      final strict = project.auditYaml('''
fail_on: warning
localization:
  optional_locales: [de]
  fail_on_optional_locales: true
''');
      expect(strict.passed, isFalse);
    });

    test('optional locales still report malformed files as errors', () {
      final project = TestProject.create({
        'assets/translations/en.json': '{"a": "A"}',
        'assets/translations/de.json': '{"a": }',
      });
      final result = project.auditYaml(
        'localization:\n  optional_locales: [de]',
      );
      expect(
        withCode(result, DiagnosticCode.invalidFile).single.severity,
        Severity.error,
      );
      expect(result.passed, isFalse);
    });
  });

  group('base locale', () {
    test('defaults to the l10n.yaml template, then en', () {
      final project = TestProject.create(
        flutterProject(
          arb: {
            'app_en.arb': '{"a": "A"}',
            'app_ur.arb': '{"a": "A", "b": "B"}',
          },
          l10nYaml: 'template-arb-file: app_ur.arb\n',
        ),
      );
      expect(project.audit().bundles.single.baseLocale, 'ur');
    });

    test('config base locale overrides the template and is validated', () {
      final project = TestProject.create({
        'assets/translations/en.json': '{"a": "A"}',
        'assets/translations/fr.json': '{"a": "A"}',
      });
      expect(
        project.auditYaml('base_locale: fr').bundles.single.baseLocale,
        'fr',
      );
      final result = project.auditYaml('base_locale: ur');
      expect(
        withCode(result, DiagnosticCode.missingLocale).single.locale,
        'ur',
      );
      expect(result.coverage, isEmpty);
    });

    test('falls back to the first locale alphabetically, with a note', () {
      final project = TestProject.create({
        'assets/translations/fr.json': '{"a": "A"}',
        'assets/translations/de.json': '{"a": "A"}',
      });
      final result = project.audit();
      expect(result.bundles.single.baseLocale, 'de');
      expect(
        withCode(
          result,
          DiagnosticCode.configuration,
        ).any((d) => d.message.contains('first alphabetically')),
        isTrue,
      );
    });
  });

  group('discovery', () {
    test('bundles are separated by directory and prefix', () {
      final project = TestProject.create({
        'lib/l10n/app_en.arb': '{"a": "A"}',
        'lib/l10n/app_fr.arb': '{"a": "A"}',
        'lib/l10n/intl_en.arb': '{"b": "B"}',
        'assets/translations/en.json': '{"c": "C"}',
      });
      final result = project.auditYaml('checks:\n  unused_keys: false');
      expect(result.bundles.map((b) => b.id), [
        'assets/translations/*.json',
        'lib/l10n/app_*.arb',
        'lib/l10n/intl_*.arb',
      ]);
    });

    test('locale mappings assign locales to arbitrary file names', () {
      final project = TestProject.create({
        'assets/translations/english.json': '{"a": "A"}',
        'assets/translations/urdu.json': '{}',
      });
      final result = project.auditYaml('''
checks:
  unused_keys: false
localization:
  locale_mappings:
    assets/translations/english.json: en
    assets/translations/urdu.json: ur
''');
      expect(result.bundles.single.locales, ['en', 'ur']);
      expect(withCode(result, DiagnosticCode.missingKey).single.locale, 'ur');
    });

    test('files without a recognizable locale are listed as skipped', () {
      final project = TestProject.create({
        'assets/translations/en.json': '{"a": "A"}',
        'assets/translations/settings.json': '{}',
      });
      final result = project.auditYaml('checks:\n  unused_keys: false');
      expect(
        result.skippedFiles.single,
        startsWith('assets/translations/settings.json'),
      );
    });

    test('no translation files is an error', () {
      final project = TestProject.create({'pubspec.yaml': 'name: x\n'});
      final result = project.audit();
      expect(result.passed, isFalse);
      expect(
        withCode(result, DiagnosticCode.configuration).single.message,
        contains('No localization directory'),
      );
    });

    test('regression: missing default lib/ is not reported, configured is', () {
      final files = {
        'pubspec.yaml': 'name: x\n',
        'assets/translations/en.json': '{"a": "A"}',
      };
      bool warns(AuditResult r) => withCode(
        r,
        DiagnosticCode.configuration,
      ).any((d) => d.message.contains('Source directory'));
      expect(warns(TestProject.create(files).audit()), isFalse);
      expect(
        warns(
          TestProject.create(files).auditYaml('source:\n  directories: [lib]'),
        ),
        isTrue,
      );
    });

    test('configured directory that does not exist is an error', () {
      final project = TestProject.create({});
      final result = project.auditYaml('localization:\n  directories: [i18n]');
      expect(
        withCode(result, DiagnosticCode.configuration).first.message,
        contains('"i18n" does not exist'),
      );
    });

    test('formats filter limits discovery', () {
      final project = TestProject.create({
        'lib/l10n/app_en.arb': '{"a": "A"}',
        'assets/translations/en.json': '{"c": "C"}',
      });
      final result = project.auditYaml(
        'checks:\n  unused_keys: false\nlocalization:\n  formats: [json]',
      );
      expect(result.bundles.single.format, 'json');
    });
  });

  test('results are deterministic', () {
    final project = TestProject.create({
      'assets/translations/en.json': '{"b": "B", "a": "A {x}", "c": ""}',
      'assets/translations/fr.json': '{"z": "Z", "a": "{y}"}',
      'assets/translations/ur.json': '{"a": "{x}", "a": "{x}"}',
      'lib/main.dart': "f() => 'q'.tr();",
    });
    final first = const JsonReporter().render(project.audit());
    final second = const JsonReporter().render(project.audit());
    expect(first, second);
  });
}
