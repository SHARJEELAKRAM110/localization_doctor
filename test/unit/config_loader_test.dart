import 'package:localization_doctor/localization_doctor.dart';
import 'package:test/test.dart';

import '../support/test_project.dart';

Matcher configError(String fragment) => throwsA(
  isA<ConfigException>().having(
    (e) => e.toString(),
    'message',
    contains(fragment),
  ),
);

void main() {
  test('empty file yields defaults', () {
    final config = parseConfig('');
    expect(config.baseLocale, isNull);
    expect(config.directories, isNull);
    expect(config.formats, {TranslationFormat.arb, TranslationFormat.json});
    expect(config.failOn, Severity.error);
    expect(config.sourceDirectories, ['lib']);
    expect(config.reportFormats, ['terminal']);
    expect(config.keyClasses, ['LocaleKeys']);
  });

  test('source.key_classes is configurable and validated', () {
    expect(parseConfig('source:\n  key_classes: [Keys, Tr]').keyClasses, [
      'Keys',
      'Tr',
    ]);
    expect(parseConfig('source:\n  key_classes: []').keyClasses, isEmpty);
    expect(
      () => parseConfig('source:\n  key_classes: [not-valid]'),
      configError('not a Dart identifier'),
    );
  });

  test('parses the full documented schema', () {
    final config = parseConfig(r'''
base_locale: en-us
fail_on: warning
localization:
  directories: [lib/l10n, assets/translations]
  formats: [arb]
  required_locales: [en, ur]
  optional_locales: [fr]
  fail_on_optional_locales: true
  locale_mappings:
    assets/translations/english.json: en
  key_separator: ":"
  json_placeholder_pattern: '\{\{(\w+)\}\}'
  arb_use_escaping: true
  arb_relax_syntax: false
source:
  directories: [lib, packages/ui/lib]
  exclude: [lib/legacy/**]
  localization_classes: [AppLocalizations, S]
  accessors: [context.l10n]
  json_lookup_functions: [tr, t]
checks:
  unused_keys: false
ignore:
  keys: [debug.*]
  unused_keys: [errors.*]
  diagnostics:
    - code: LOC008
      locale: fr
      key: legacy.*
severity:
  LOC008: error
reports:
  formats: [terminal, json]
  output_directory: reports
''');
    expect(config.baseLocale, 'en_US');
    expect(config.failOn, Severity.warning);
    expect(config.directories, ['lib/l10n', 'assets/translations']);
    expect(config.formats, {TranslationFormat.arb});
    expect(config.requiredLocales, ['en', 'ur']);
    expect(config.optionalLocales, ['fr']);
    expect(config.failOnOptionalLocales, isTrue);
    expect(config.localeMappings, {'assets/translations/english.json': 'en'});
    expect(config.keySeparator, ':');
    expect(config.arbUseEscaping, isTrue);
    expect(config.arbRelaxSyntax, isFalse);
    expect(config.sourceDirectories, ['lib', 'packages/ui/lib']);
    expect(config.localizationClasses, ['AppLocalizations', 'S']);
    expect(config.accessors, ['context.l10n']);
    expect(config.jsonLookupFunctions, ['tr', 't']);
    expect(config.checks.unusedKeys, isFalse);
    expect(config.checks.missingKeys, isTrue);
    expect(config.ignore.keys.single.matches('debug.banner'), isTrue);
    expect(config.ignore.unusedKeys.single.matches('errors.x'), isTrue);
    final rule = config.ignore.rules.single;
    expect(rule.code, DiagnosticCode.extraKey);
    expect(rule.locale, 'fr');
    expect(rule.key!.matches('legacy.title'), isTrue);
    expect(config.severityOverrides, {DiagnosticCode.extraKey: Severity.error});
    expect(config.reportFormats, ['terminal', 'json']);
    expect(config.outputDirectory, 'reports');
  });

  group('validation', () {
    test('unknown keys suggest the closest name', () {
      expect(
        () => parseConfig('base_locle: en'),
        configError('Did you mean "base_locale"'),
      );
      expect(
        () => parseConfig('checks:\n  missing_key: true'),
        configError('Unknown configuration key "checks.missing_key"'),
      );
    });

    test('reports line and column', () {
      try {
        parseConfig('localization:\n  formats: [xml]', sourcePath: 'c.yaml');
        fail('expected exception');
      } on ConfigException catch (e) {
        expect(e.toString(), startsWith('c.yaml:2:'));
        expect(e.message, contains('Unsupported format "xml"'));
      }
    });

    test('rejects wrong types', () {
      expect(
        () => parseConfig('localization: []'),
        configError('must be a map'),
      );
      expect(
        () => parseConfig('localization:\n  directories: lib'),
        configError('must be a list of strings'),
      );
      expect(
        () => parseConfig('checks:\n  unused_keys: yes please'),
        configError('must be true or false'),
      );
    });

    test('rejects invalid locales', () {
      expect(
        () => parseConfig('base_locale: english'),
        configError('not a valid locale'),
      );
      expect(
        () =>
            parseConfig('localization:\n  required_locales: [en, xx_yy_zz_w]'),
        configError('not a valid locale'),
      );
    });

    test('a locale cannot be both required and optional', () {
      expect(
        () => parseConfig(
          'localization:\n  required_locales: [fr]\n  optional_locales: [fr]',
        ),
        configError('both required and optional'),
      );
    });

    test('rejects invalid regular expressions', () {
      expect(
        () => parseConfig("localization:\n  json_placeholder_pattern: '([a-z'"),
        configError('Invalid regular expression'),
      );
      expect(
        () => parseConfig("localization:\n  json_placeholder_pattern: 'x*'"),
        configError('must not match empty text'),
      );
    });

    test('rejects paths outside the project', () {
      expect(
        () => parseConfig('localization:\n  directories: [../other]'),
        configError('inside the project root'),
      );
    });

    test('LOC006 can never be ignored or downgraded', () {
      expect(
        () => parseConfig('ignore:\n  diagnostics:\n    - code: LOC006'),
        configError('cannot be ignored'),
      );
      expect(
        () => parseConfig('severity:\n  LOC006: warning'),
        configError('always an error'),
      );
    });

    test('ignore rules need at least one criterion', () {
      expect(
        () => parseConfig('ignore:\n  diagnostics:\n    - {}'),
        configError('at least one of'),
      );
    });

    test('unknown diagnostic codes are rejected', () {
      expect(
        () => parseConfig('severity:\n  LOC999: error'),
        configError('Unknown diagnostic code'),
      );
    });

    test('invalid YAML is a ConfigException', () {
      expect(() => parseConfig('a: [b'), configError('Invalid YAML'));
    });
  });

  group('loadConfig', () {
    test('uses localization_doctor.yaml from the project root', () {
      final project = TestProject.create({
        'localization_doctor.yaml': 'base_locale: ur\n',
      });
      expect(loadConfig(project.root).baseLocale, 'ur');
    });

    test('missing default file yields defaults', () {
      final project = TestProject.create({});
      expect(loadConfig(project.root).baseLocale, isNull);
    });

    test('missing explicit file is an error', () {
      final project = TestProject.create({});
      expect(
        () =>
            loadConfig(project.root, explicitPath: '${project.root}/nope.yaml'),
        configError('not found'),
      );
    });
  });

  group('KeyPattern', () {
    test('exact and wildcard matching', () {
      expect(KeyPattern('home.title').matches('home.title'), isTrue);
      expect(KeyPattern('home.title').matches('home.titles'), isFalse);
      expect(KeyPattern('home.*').matches('home.menu.open'), isTrue);
      expect(KeyPattern('a?c').matches('abc'), isTrue);
      expect(
        KeyPattern('a.c').matches('abc'),
        isFalse,
        reason: 'dot is literal',
      );
    });
  });
}
