import 'dart:io';

import 'package:localization_doctor/localization_doctor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_project.dart';

List<String> configMessages(AuditResult result) => [
  for (final d in withCode(result, DiagnosticCode.configuration)) d.message,
];

void main() {
  const arb = {'app_en.arb': '{"a": "A"}', 'app_fr.arb': '{"a": "A"}'};
  const main = 'f(c) => AppLocalizations.of(c)!.a;';

  test('missing generate flag and dependencies are reported', () {
    final project = TestProject.create({
      ...flutterProject(arb: arb, main: main, generate: false),
      'pubspec.yaml': 'name: x\ndependencies:\n  flutter:\n    sdk: flutter\n',
    });
    final messages = configMessages(project.audit());
    expect(messages.where((m) => m.contains('generate: true')), hasLength(1));
    expect(
      messages.where((m) => m.contains('`flutter_localizations`')),
      hasLength(1),
    );
    expect(messages.where((m) => m.contains('`intl`')), hasLength(1));
  });

  test('pure Dart projects are not asked for Flutter settings', () {
    final project = TestProject.create({
      'pubspec.yaml': 'name: x\n',
      for (final e in arb.entries) 'lib/l10n/${e.key}': e.value,
      'lib/main.dart': main,
    });
    expect(
      configMessages(project.audit()).where((m) => m.contains('generate')),
      isEmpty,
    );
  });

  test('missing pubspec.yaml is a warning', () {
    final project = TestProject.create({
      'assets/translations/en.json': '{"a": "A"}',
    });
    expect(
      configMessages(project.audit()),
      contains('No pubspec.yaml found in the project root.'),
    );
  });

  test('invalid arb-dir and template file are errors', () {
    final project = TestProject.create(
      flutterProject(arb: arb, main: main, l10nYaml: 'arb-dir: lib/i18n\n'),
    );
    expect(
      configMessages(project.audit()),
      contains(contains('arb-dir "lib/i18n"')),
    );

    final project2 = TestProject.create(
      flutterProject(
        arb: arb,
        main: main,
        l10nYaml: 'template-arb-file: app_de.arb\n',
      ),
    );
    final result = project2.audit();
    expect(
      withCode(
        result,
        DiagnosticCode.configuration,
      ).firstWhere((d) => d.message.contains('app_de.arb')).severity,
      Severity.error,
    );
  });

  test('synthetic-package: true is an error', () {
    final project = TestProject.create(
      flutterProject(
        arb: arb,
        main: main,
        l10nYaml: 'synthetic-package: true\n',
      ),
    );
    expect(
      configMessages(project.audit()),
      contains(contains('synthetic-package')),
    );
  });

  test('missing generated file is informational', () {
    final project = TestProject.create(flutterProject(arb: arb, main: main));
    final d = withCode(
      project.audit(),
      DiagnosticCode.configuration,
    ).firstWhere((d) => d.message.contains('was not found'));
    expect(d.severity, Severity.info);
    expect(d.confidence, Confidence.probable);
  });

  test('generated code missing a locale is stale', () {
    final project = TestProject.create({
      ...flutterProject(arb: arb, main: main),
      'lib/l10n/app_localizations.dart': '// generated',
      'lib/l10n/app_localizations_en.dart': '// generated',
    });
    final messages = configMessages(project.audit());
    expect(messages, contains(contains('no generated file for fr')));
  });

  test('ARB files newer than generated code are flagged as possibly stale', () {
    final project = TestProject.create({
      ...flutterProject(arb: arb, main: main),
      'lib/l10n/app_localizations.dart': '// generated',
      'lib/l10n/app_localizations_en.dart': '// generated',
      'lib/l10n/app_localizations_fr.dart': '// generated',
    });
    final old = DateTime(2020);
    for (final name in [
      'app_localizations.dart',
      'app_localizations_en.dart',
      'app_localizations_fr.dart',
    ]) {
      File(p.join(project.root, 'lib', 'l10n', name)).setLastModifiedSync(old);
    }
    final messages = configMessages(project.audit());
    expect(messages, contains(contains('may be stale')));
  });

  test('template locale differing from base locale is a warning', () {
    final project = TestProject.create(flutterProject(arb: arb, main: main));
    final result = project.auditYaml('base_locale: fr');
    expect(configMessages(result), contains(contains('as the template')));
  });

  test('literal supportedLocales are compared with translation files', () {
    final project = TestProject.create(
      flutterProject(
        arb: arb,
        main: '''
f(c) => MaterialApp(
  title: AppLocalizations.of(c)!.a,
  supportedLocales: const [Locale('en'), Locale('ur')],
);
''',
      ),
    );
    final messages = configMessages(project.audit());
    expect(messages, contains(contains('lists "ur", but no translation file')));
    expect(messages, contains(contains('Translations exist for "fr"')));
  });

  test('JSON translations under assets/ must be declared as assets', () {
    final files = {
      'assets/translations/en.json': '{"a": "A"}',
      'lib/main.dart': "f() => 'a'.tr();",
    };
    final undeclared = TestProject.create({
      ...files,
      'pubspec.yaml': 'name: x\nflutter:\n  uses-material-design: true\n',
    });
    expect(
      configMessages(undeclared.audit()),
      contains(contains('not declared as Flutter assets')),
    );
    final declared = TestProject.create({
      ...files,
      'pubspec.yaml':
          'name: x\nflutter:\n  assets:\n    - assets/translations/\n',
    });
    expect(
      configMessages(declared.audit()).where((m) => m.contains('assets')),
      isEmpty,
    );
  });

  test('configuration check never writes to the project', () {
    final project = TestProject.create(flutterProject(arb: arb, main: main));
    final before = Directory(
      project.root,
    ).listSync(recursive: true).map((e) => e.path).toSet();
    project.audit();
    final after = Directory(
      project.root,
    ).listSync(recursive: true).map((e) => e.path).toSet();
    expect(after, before);
  });
}
