import 'dart:convert';
import 'dart:io';

import 'package:localization_doctor/localization_doctor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_project.dart';

Map<String, String> passingProject() => {
  'pubspec.yaml': 'name: demo\n',
  'assets/translations/en.json': '{"home": {"title": "Home"}}',
  'assets/translations/ur.json': '{"home": {"title": "ہوم"}}',
  'assets/translations/fr.json': '{"home": {"title": "Accueil"}}',
  'lib/main.dart': "f() => 'home.title'.tr();",
};

void main() {
  group('exit codes', () {
    test('0 when the audit passes', () async {
      final project = TestProject.create(passingProject());
      final run = await runCliCaptured(['audit', '--path', project.root]);
      expect(run.exitCode, ExitCodes.success, reason: run.stdout + run.stderr);
      expect(run.stdout, contains('PASSED'));
    });

    test('1 when errors are found', () async {
      final project = TestProject.create({
        ...passingProject(),
        'assets/translations/fr.json': '{}',
      });
      final run = await runCliCaptured(['audit', '--path', project.root]);
      expect(run.exitCode, ExitCodes.violations);
      expect(run.stdout, contains('LOC001'));
    });

    test('warnings: 0 by default, 1 with --strict', () async {
      final project = TestProject.create({
        ...passingProject(),
        'assets/translations/fr.json':
            '{"home": {"title": "Accueil"}, "extra": "x"}',
      });
      final normal = await runCliCaptured(['--path', project.root]);
      expect(normal.exitCode, ExitCodes.success);
      final strict = await runCliCaptured(['--path', project.root, '--strict']);
      expect(strict.exitCode, ExitCodes.violations);
    });

    test('2 for unknown options', () async {
      final run = await runCliCaptured(['audit', '--nope']);
      expect(run.exitCode, ExitCodes.usage);
      expect(run.stderr, contains('Could not find an option named'));
    });

    test('2 for --verbose with --quiet', () async {
      final run = await runCliCaptured(['audit', '-v', '-q']);
      expect(run.exitCode, ExitCodes.usage);
    });

    test('2 for an invalid format and an invalid base locale', () async {
      expect((await runCliCaptured(['audit', '--format', 'xml'])).exitCode, 2);
      final project = TestProject.create(passingProject());
      final run = await runCliCaptured([
        'audit',
        '--path',
        project.root,
        '--base-locale',
        'english',
      ]);
      expect(run.exitCode, ExitCodes.usage);
      expect(run.stderr, contains('Invalid --base-locale'));
    });

    test('2 for invalid configuration, with location', () async {
      final project = TestProject.create({
        ...passingProject(),
        'localization_doctor.yaml': 'checks:\n  bogus: true\n',
      });
      final run = await runCliCaptured(['--path', project.root]);
      expect(run.exitCode, ExitCodes.usage);
      expect(run.stderr, contains('localization_doctor.yaml:2:3'));
      expect(run.stderr, contains('Unknown configuration key "checks.bogus"'));
    });

    test('2 for a missing --config file', () async {
      final project = TestProject.create(passingProject());
      final run = await runCliCaptured([
        '--path',
        project.root,
        '--config',
        p.join(project.root, 'missing.yaml'),
      ]);
      expect(run.exitCode, ExitCodes.usage);
    });

    test('3 when the project directory does not exist', () async {
      final run = await runCliCaptured([
        '--path',
        p.join(Directory.systemTemp.path, 'definitely_missing_dir_xyz'),
      ]);
      expect(run.exitCode, ExitCodes.failure);
      expect(run.stderr, contains('does not exist'));
    });
  });

  group('options', () {
    test('--version and --help', () async {
      final version = await runCliCaptured(['--version']);
      expect(version.exitCode, 0);
      expect(version.stdout.trim(), 'localization_doctor $packageVersion');
      final help = await runCliCaptured(['--help']);
      expect(help.exitCode, 0);
      final auditHelp = await runCliCaptured(['audit', '--help']);
      expect(auditHelp.stdout, contains('--base-locale'));
      expect(auditHelp.stdout, contains('--strict'));
    });

    test('no arguments runs the audit in the current directory', () async {
      final project = TestProject.create(passingProject());
      final previous = Directory.current;
      Directory.current = project.root;
      addTearDown(() => Directory.current = previous);
      final run = await runCliCaptured([]);
      expect(run.exitCode, 0);
      expect(run.stdout, contains('Localization Doctor'));
    });

    test('--format json prints only JSON to stdout', () async {
      final project = TestProject.create(passingProject());
      final run = await runCliCaptured([
        '--path',
        project.root,
        '--format',
        'json',
      ]);
      final json = jsonDecode(run.stdout) as Map<String, dynamic>;
      expect(json['status'], 'passed');
      expect(json['coverage'], hasLength(3));
      expect(run.stdout, isNot(contains('\x1B')));
    });

    test('--format html prints a document to stdout', () async {
      final project = TestProject.create(passingProject());
      final run = await runCliCaptured(['--path', project.root, '-f', 'html']);
      expect(run.stdout, startsWith('<!doctype html>'));
    });

    test('multiple formats write files to --output-dir', () async {
      final project = TestProject.create(passingProject());
      final out = p.join(project.root, 'reports');
      final run = await runCliCaptured([
        '--path',
        project.root,
        '--format',
        'terminal,json,html',
        '--output-dir',
        out,
      ]);
      expect(run.exitCode, 0);
      expect(run.stdout, contains('PASSED'));
      final json = File(p.join(out, 'localization_doctor_report.json'));
      final html = File(p.join(out, 'localization_doctor_report.html'));
      expect(jsonDecode(json.readAsStringSync()), isA<Map<String, dynamic>>());
      expect(html.readAsStringSync(), contains('<html'));
      expect(run.stderr, contains('Report written to'));
    });

    test(
      'reports.formats from config writes to the default directory',
      () async {
        final project = TestProject.create({
          ...passingProject(),
          'localization_doctor.yaml': 'reports:\n  formats: [terminal, json]\n',
        });
        final run = await runCliCaptured(['--path', project.root]);
        expect(run.exitCode, 0);
        expect(
          project.exists(
            'build/localization_doctor/localization_doctor_report.json',
          ),
          isTrue,
        );
      },
    );

    test('--base-locale overrides the configuration file', () async {
      final project = TestProject.create({
        ...passingProject(),
        'assets/translations/fr.json':
            '{"home": {"title": "Accueil"}, "x": "y"}',
        'localization_doctor.yaml': 'base_locale: en\n',
      });
      final run = await runCliCaptured([
        '--path',
        project.root,
        '--base-locale',
        'fr',
        '--format',
        'json',
      ]);
      final json = jsonDecode(run.stdout) as Map<String, dynamic>;
      final bundle = (json['bundles'] as List<dynamic>).single as Map;
      expect(bundle['baseLocale'], 'fr');
      expect(run.exitCode, 1, reason: '"x" is missing from en and ur');
    });

    test('--quiet prints only the summary', () async {
      final project = TestProject.create(passingProject());
      final run = await runCliCaptured(['--path', project.root, '--quiet']);
      expect(run.stdout.trim().split('\n'), hasLength(2));
    });

    test('--color forces ANSI output', () async {
      final project = TestProject.create(passingProject());
      final run = await runCliCaptured(['--path', project.root, '--color']);
      expect(run.stdout, contains('\x1B['));
    });
  });

  group('init', () {
    test('creates a starter config that the audit accepts', () async {
      final project = TestProject.create({
        ...passingProject(),
        'l10n.yaml': 'output-class: S\n',
        'lib/l10n/app_en.arb': '{"a": "A"}',
      });
      final run = await runCliCaptured(['init', '--path', project.root]);
      expect(run.exitCode, 0, reason: run.stderr);
      final content = project.read('localization_doctor.yaml');
      final config = parseConfig(content);
      expect(config.baseLocale, 'en');
      expect(config.directories, ['lib/l10n', 'assets/translations']);
      expect(config.requiredLocales, ['en', 'fr', 'ur']);
      expect(config.localizationClasses, ['S']);
      expect(content, contains('key_classes:'));
      expect(config.keyClasses, ['LocaleKeys']);
      final audit = await runCliCaptured(['--path', project.root]);
      expect(audit.exitCode, isNot(ExitCodes.usage));
    });

    test('never overwrites an existing file', () async {
      final project = TestProject.create({
        'localization_doctor.yaml': '# mine\n',
      });
      final run = await runCliCaptured(['init', '--path', project.root]);
      expect(run.exitCode, ExitCodes.usage);
      expect(run.stderr, contains('already exists'));
      expect(project.read('localization_doctor.yaml'), '# mine\n');
    });
  });

  group('example projects', () {
    test('sample_app produces exactly the planted findings', () async {
      final run = await runCliCaptured([
        '--path',
        'example/sample_app',
        '--format',
        'json',
      ]);
      expect(run.exitCode, ExitCodes.violations);
      final json = jsonDecode(run.stdout) as Map<String, dynamic>;
      final found = [
        for (final d
            in (json['diagnostics'] as List<dynamic>)
                .cast<Map<String, dynamic>>())
          '${d['code']} ${d['severity']} ${d['locale']} ${d['key']}',
      ];
      expect(found, [
        'LOC001 error ur settingsTitle',
        'LOC004 error fr greeting',
        'LOC002 warning en legacyBanner',
        'LOC004 warning fr greeting',
        'LOC005 warning fr logout',
        'LOC007 info null null',
      ]);
      final coverage = {
        for (final c
            in (json['coverage'] as List<dynamic>).cast<Map<String, dynamic>>())
          c['locale']: c['coverage'],
      };
      expect(coverage, {'en': 100.0, 'fr': 85.7, 'ur': 85.7});
    });

    test('broken_project reports every intentional problem', () async {
      final run = await runCliCaptured([
        '--path',
        'example/broken_project',
        '--format',
        'json',
      ]);
      expect(run.exitCode, ExitCodes.violations);
      final json = jsonDecode(run.stdout) as Map<String, dynamic>;
      final codes = {
        for (final d
            in (json['diagnostics'] as List<dynamic>)
                .cast<Map<String, dynamic>>())
          d['code'],
      };
      expect(
        codes,
        containsAll([
          'LOC002',
          'LOC003',
          'LOC004',
          'LOC006',
          'LOC010',
          'LOC011',
          'LOC015',
          'LOC016',
        ]),
      );
    });
  });

  group('executable', () {
    // Runs the real entry point in a separate process to verify exit codes
    // and stream separation end to end.
    Future<ProcessResult> runBin(List<String> args) => Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/localization_doctor.dart', ...args],
      environment: {'NO_COLOR': '1'},
    );

    test(
      '--version and audit exit codes',
      () async {
        final version = await runBin(['--version']);
        expect(version.exitCode, 0, reason: '${version.stderr}');
        expect(
          (version.stdout as String).trim(),
          'localization_doctor $packageVersion',
        );
        final audit = await runBin(['--path', 'example/sample_app']);
        expect(audit.exitCode, 1, reason: '${audit.stderr}');
        expect(audit.stdout as String, isNot(contains('\x1B')));
        expect(audit.stdout as String, contains('FAILED'));
        final usage = await runBin(['--bogus']);
        expect(usage.exitCode, 2);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
