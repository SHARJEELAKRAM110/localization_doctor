import 'dart:io';

import 'package:localization_doctor/localization_doctor.dart';
import 'package:localization_doctor/src/cli/cli_io.dart';
import 'package:localization_doctor/src/cli/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A temporary project directory, deleted automatically after the test.
class TestProject {
  TestProject._(this.root);

  /// Creates a project with [files] (relative path -> content). Paths use
  /// forward slashes and are created with the platform separator.
  factory TestProject.create(Map<String, String> files) {
    final dir = Directory.systemTemp.createTempSync('loc_doctor_test_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final project = TestProject._(dir.path);
    files.forEach(project.write);
    return project;
  }

  final String root;

  void write(String relative, String content) {
    final file = File(p.joinAll([root, ...relative.split('/')]));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  bool exists(String relative) =>
      File(p.joinAll([root, ...relative.split('/')])).existsSync();

  String read(String relative) =>
      File(p.joinAll([root, ...relative.split('/')])).readAsStringSync();

  AuditResult audit([DoctorConfig? config]) => LocalizationAuditor(
    projectPath: root,
    config: config ?? loadConfig(root),
    clock: () => DateTime.utc(2026, 1, 1),
  ).run();

  AuditResult auditYaml(String yaml) => audit(parseConfig(yaml));
}

/// Output of an in-process CLI run.
class CliRun {
  CliRun(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

Future<CliRun> runCliCaptured(List<String> args) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(
    args,
    io: CliIo(out: out, err: err, supportsColor: false),
  );
  return CliRun(code, out.toString(), err.toString());
}

/// A minimal Flutter gen-l10n project.
Map<String, String> flutterProject({
  Map<String, String> arb = const {},
  String? main,
  String? l10nYaml = 'arb-dir: lib/l10n\ntemplate-arb-file: app_en.arb\n',
  bool generate = true,
}) => {
  'pubspec.yaml':
      '''
name: demo
environment:
  sdk: ^3.11.0
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  intl: any
flutter:
  generate: $generate
''',
  'l10n.yaml': ?l10nYaml,
  for (final entry in arb.entries) 'lib/l10n/${entry.key}': entry.value,
  'lib/main.dart': ?main,
};

Iterable<Diagnostic> withCode(AuditResult result, DiagnosticCode code) =>
    result.diagnostics.where((d) => d.code == code);
