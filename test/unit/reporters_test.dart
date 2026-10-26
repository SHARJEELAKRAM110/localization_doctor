import 'dart:convert';
import 'dart:io';

import 'package:localization_doctor/localization_doctor.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

AuditResult sampleResult({List<Diagnostic>? diagnostics}) => AuditResult(
  toolVersion: packageVersion,
  projectPath: '/work/app',
  generatedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
  failOn: Severity.error,
  diagnostics:
      diagnostics ??
      [
        const Diagnostic(
          code: DiagnosticCode.unusedKey,
          severity: Severity.warning,
          message: 'Key "b" appears to be unused.',
          location: SourceLocation('lib/l10n/app_en.arb', line: 3, column: 3),
          key: 'b',
          locale: 'en',
          bundle: 'lib/l10n/app_*.arb',
        ),
        const Diagnostic(
          code: DiagnosticCode.missingKey,
          severity: Severity.error,
          message: 'Key "a" is missing from fr.',
          location: SourceLocation('lib/l10n/app_fr.arb'),
          relatedLocations: [
            SourceLocation('lib/l10n/app_en.arb', line: 2, column: 3),
          ],
          key: 'a',
          locale: 'fr',
          bundle: 'lib/l10n/app_*.arb',
          suggestion: 'Add "a" to app_fr.arb.',
        ),
      ],
  coverage: const [
    LocaleCoverage(
      bundle: 'lib/l10n/app_*.arb',
      locale: 'en',
      isBase: true,
      isOptional: false,
      total: 3,
      translated: 3,
      missing: 0,
      empty: 0,
      invalid: 0,
    ),
    LocaleCoverage(
      bundle: 'lib/l10n/app_*.arb',
      locale: 'fr',
      isBase: false,
      isOptional: false,
      total: 3,
      translated: 2,
      missing: 1,
      empty: 0,
      invalid: 0,
    ),
  ],
  bundles: const [],
);

void main() {
  group('LocaleCoverage', () {
    test('percent is rounded to one decimal place', () {
      LocaleCoverage c(int total, int translated) => LocaleCoverage(
        bundle: 'b',
        locale: 'x',
        isBase: false,
        isOptional: false,
        total: total,
        translated: translated,
        missing: total - translated,
        empty: 0,
        invalid: 0,
      );
      expect(c(120, 105).percent, 87.5);
      expect(c(3, 2).percent, 66.7);
      expect(c(7, 6).percent, 85.7);
      expect(c(0, 0).percent, 100);
    });
  });

  group('AuditResult', () {
    test('sorts diagnostics deterministically, errors first', () {
      final result = sampleResult();
      expect(result.diagnostics.map((d) => d.code.id), ['LOC001', 'LOC002']);
    });

    test('passed depends on failOn', () {
      final warningOnly = sampleResult(
        diagnostics: [
          const Diagnostic(
            code: DiagnosticCode.extraKey,
            severity: Severity.warning,
            message: 'w',
          ),
        ],
      );
      expect(warningOnly.passed, isTrue);
      final strict = AuditResult(
        toolVersion: '0',
        projectPath: '/',
        generatedAt: DateTime.utc(2026),
        failOn: Severity.warning,
        diagnostics: warningOnly.diagnostics,
        coverage: const [],
        bundles: const [],
      );
      expect(strict.passed, isFalse);
    });
  });

  group('JsonReporter', () {
    test('produces valid JSON with the documented fields', () {
      final json =
          jsonDecode(const JsonReporter().render(sampleResult()))
              as Map<String, dynamic>;
      expect(json['schemaVersion'], 1);
      expect(json['tool'], {
        'name': 'localization_doctor',
        'version': packageVersion,
      });
      expect(json['projectPath'], '/work/app');
      expect(json['generatedAt'], '2026-01-02T03:04:05.000Z');
      expect(json['status'], 'failed');
      expect(json['summary'], {
        'errors': 1,
        'warnings': 1,
        'infos': 0,
        'violations': 1,
        'suppressed': 0,
        'scannedSourceFiles': 0,
      });
      final diagnostics = json['diagnostics'] as List<dynamic>;
      final first = diagnostics.first as Map<String, dynamic>;
      expect(first['code'], 'LOC001');
      expect(first['severity'], 'error');
      expect(first['confidence'], 'definite');
      expect(first['location'], {
        'path': 'lib/l10n/app_fr.arb',
        'line': null,
        'column': null,
      });
      expect(first['suggestion'], 'Add "a" to app_fr.arb.');
      expect(
        (json['coverage'] as List<dynamic>).last,
        containsPair('coverage', 66.7),
      );
    });

    test('contains no ANSI escape codes', () {
      expect(
        const JsonReporter().render(sampleResult()),
        isNot(contains('\x1B')),
      );
    });
  });

  group('TerminalReporter', () {
    test('renders summary, coverage and fixes without color', () {
      final text = const TerminalReporter().render(sampleResult());
      expect(text, isNot(contains('\x1B')));
      expect(text, contains('Locale coverage'));
      expect(text, contains('fr'));
      expect(text, contains('66.7%'));
      expect(text, contains('error   LOC001  lib/l10n/app_fr.arb'));
      expect(text, contains('fix: Add "a" to app_fr.arb.'));
      expect(text, contains('Summary: 1 error, 1 warning, 0 info'));
      expect(
        text,
        contains('FAILED: 1 violation at or above "error" severity'),
      );
    });

    test('uses ANSI colors only when enabled', () {
      expect(
        const TerminalReporter(color: true).render(sampleResult()),
        contains('\x1B[31m'),
      );
    });

    test('quiet prints only the summary', () {
      final text = const TerminalReporter(
        verbosity: Verbosity.quiet,
      ).render(sampleResult());
      expect(text.trim().split('\n'), hasLength(2));
    });

    test('verbose shows related locations', () {
      final text = const TerminalReporter(
        verbosity: Verbosity.verbose,
      ).render(sampleResult());
      expect(text, contains('see also: lib/l10n/app_en.arb:2:3'));
      expect(text, contains('Dart files scanned'));
    });

    test('passing audit says PASSED', () {
      final text = const TerminalReporter().render(
        sampleResult(diagnostics: []),
      );
      expect(text, contains('No localization problems found.'));
      expect(text, contains('PASSED'));
    });
  });

  group('HtmlReporter', () {
    test('escapeHtml escapes all special characters', () {
      expect(
        escapeHtml('<script>alert("x")</script> & \'y\' `z`'),
        '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; '
        '&#39;y&#39; &#96;z&#96;',
      );
    });

    test('untrusted content cannot inject markup', () {
      const evil = '<img src=x onerror=alert(1)>"\'';
      final html = const HtmlReporter().render(
        sampleResult(
          diagnostics: [
            const Diagnostic(
              code: DiagnosticCode.missingKey,
              severity: Severity.error,
              message: 'Key "$evil" is missing.',
              key: evil,
              locale: 'fr',
              location: SourceLocation('lib/$evil.arb', line: 1, column: 1),
              suggestion: 'Add $evil',
              relatedLocations: [SourceLocation('</td><script>')],
            ),
          ],
        ),
      );
      expect(html, isNot(contains('<img')));
      expect(html, isNot(contains('</td><script>')));
      expect(html.split('<script>'), hasLength(2), reason: 'only our script');
      expect(html, contains('&lt;img src=x onerror=alert(1)&gt;'));
    });

    test('is self-contained', () {
      final html = const HtmlReporter().render(sampleResult());
      expect(html, startsWith('<!doctype html>'));
      expect(html, isNot(contains('http://')));
      expect(html, isNot(contains('https://')));
      expect(html, isNot(contains('<link')));
      expect(html, isNot(contains(' src=')));
      expect(html, contains('Locale coverage'));
      expect(html, contains('LOC001'));
      expect(html, contains('id="q"'), reason: 'search filter');
    });
  });

  group('stable contract', () {
    test('diagnostic codes are stable and unique', () {
      final ids = {for (final c in DiagnosticCode.values) c.name: c.id};
      expect(ids, {
        'missingKey': 'LOC001',
        'unusedKey': 'LOC002',
        'duplicateKey': 'LOC003',
        'placeholderMismatch': 'LOC004',
        'emptyValue': 'LOC005',
        'invalidFile': 'LOC006',
        'configuration': 'LOC007',
        'extraKey': 'LOC008',
        'invalidValueType': 'LOC009',
        'messageSyntax': 'LOC010',
        'structureMismatch': 'LOC011',
        'emptyLocaleFile': 'LOC012',
        'missingLocale': 'LOC013',
        'arbMetadata': 'LOC014',
        'dynamicKeyUsage': 'LOC015',
        'undefinedKey': 'LOC016',
      });
      expect(ids.values.toSet(), hasLength(ids.length));
    });

    test('every code is documented in the README', () {
      final readme = File('README.md').readAsStringSync();
      for (final code in DiagnosticCode.values) {
        expect(readme, contains('`${code.id}`'), reason: code.id);
      }
    });

    test('exit codes', () {
      expect(
        [
          ExitCodes.success,
          ExitCodes.violations,
          ExitCodes.usage,
          ExitCodes.failure,
        ],
        [0, 1, 2, 3],
      );
    });

    test('packageVersion matches pubspec.yaml and CHANGELOG.md', () {
      final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
      expect(packageVersion, pubspec['version']);
      expect(
        File('CHANGELOG.md').readAsStringSync(),
        contains('## $packageVersion'),
      );
    });
  });
}
