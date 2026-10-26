import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../auditor.dart';
import '../../config/config_loader.dart';
import '../../discovery/locale_name.dart';
import '../../models/audit_result.dart';
import '../../models/diagnostic.dart';
import '../../reporters/html_reporter.dart';
import '../../reporters/json_reporter.dart';
import '../../reporters/terminal_reporter.dart';
import '../cli_io.dart';
import '../exit_codes.dart';

/// Default directory (relative to the project) for report files.
const defaultReportDirectory = 'build/localization_doctor';

class AuditCommand extends Command<int> {
  AuditCommand(this.io) {
    argParser
      ..addOption(
        'path',
        abbr: 'p',
        help: 'Project directory to audit.',
        defaultsTo: '.',
      )
      ..addOption(
        'config',
        abbr: 'c',
        help:
            'Configuration file. Defaults to <path>/localization_doctor.yaml '
            'when it exists.',
      )
      ..addOption(
        'base-locale',
        abbr: 'b',
        help:
            'Reference locale that other locales are compared with. '
            'Overrides base_locale from the configuration file.',
      )
      ..addMultiOption(
        'format',
        abbr: 'f',
        help:
            'Report format(s). A single json or html format is written to '
            'stdout unless --output-dir is given; with several formats, '
            'json/html reports are written to files.',
        allowed: supportedReportFormats,
      )
      ..addOption(
        'output-dir',
        abbr: 'o',
        help:
            'Directory for json/html report files '
            '(default: <path>/$defaultReportDirectory).',
      )
      ..addFlag(
        'strict',
        negatable: false,
        help: 'Fail on warnings as well as errors.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Show related locations, scanned files and skipped files.',
      )
      ..addFlag(
        'quiet',
        abbr: 'q',
        negatable: false,
        help: 'Print only the summary line.',
      )
      ..addFlag(
        'color',
        help:
            'Force colored output on or off. By default colors are used '
            'only on terminals that support them and when NO_COLOR is unset.',
      );
  }

  final CliIo io;

  @override
  void printUsage() => io.out.writeln(usage);

  @override
  String get name => 'audit';

  @override
  String get description =>
      'Audit translation files and Dart sources (the default command).';

  @override
  Future<int> run() async {
    final args = argResults!;
    final verbose = args['verbose'] as bool;
    final quiet = args['quiet'] as bool;
    if (verbose && quiet) {
      usageException('--verbose and --quiet cannot be used together.');
    }
    final projectPath = args['path'] as String;
    if (!Directory(projectPath).existsSync()) {
      io.err.writeln('Error: project directory "$projectPath" does not exist.');
      return ExitCodes.failure;
    }

    var config = loadConfig(
      projectPath,
      explicitPath: args['config'] as String?,
    );

    final baseLocaleArg = args['base-locale'] as String?;
    if (baseLocaleArg != null) {
      final normalized = _normalizeLocaleArg(baseLocaleArg);
      config = config.copyWith(baseLocale: normalized);
    }
    if (args['strict'] as bool &&
        config.failOn.index > Severity.warning.index) {
      config = config.copyWith(failOn: Severity.warning);
    }
    final formats = args.wasParsed('format')
        ? (args['format'] as List<String>).toSet().toList()
        : config.reportFormats;
    final outputDirArg = args['output-dir'] as String?;

    final AuditResult result;
    try {
      result = LocalizationAuditor(
        projectPath: projectPath,
        config: config,
      ).run();
    } on AuditException catch (e) {
      io.err.writeln('Error: ${e.message}');
      return ExitCodes.failure;
    }

    final useColor = args.wasParsed('color')
        ? args['color'] as bool
        : io.supportsColor;
    final terminal = TerminalReporter(
      color: useColor,
      verbosity: quiet
          ? Verbosity.quiet
          : verbose
          ? Verbosity.verbose
          : Verbosity.normal,
    );

    final fileFormats = formats.where((f) => f != 'terminal').toList();
    final toStdout =
        formats.length == 1 &&
        fileFormats.length == 1 &&
        outputDirArg == null &&
        config.outputDirectory == null;

    if (toStdout) {
      io.out.write(_render(fileFormats.single, result));
    } else {
      if (formats.contains('terminal')) io.out.write(terminal.render(result));
      if (fileFormats.isNotEmpty) {
        final dir =
            outputDirArg ??
            (config.outputDirectory == null
                ? p.join(projectPath, defaultReportDirectory)
                : p.isAbsolute(config.outputDirectory!)
                ? config.outputDirectory!
                : p.join(projectPath, config.outputDirectory!));
        try {
          Directory(dir).createSync(recursive: true);
          for (final format in fileFormats) {
            final file = File(
              p.join(dir, 'localization_doctor_report.$format'),
            );
            file.writeAsStringSync(_render(format, result));
            if (!quiet) io.err.writeln('Report written to ${file.path}');
          }
        } on FileSystemException catch (e) {
          io.err.writeln(
            'Error: cannot write report to "$dir": '
            '${e.osError?.message ?? e.message}',
          );
          return ExitCodes.failure;
        }
      }
    }
    return result.passed ? ExitCodes.success : ExitCodes.violations;
  }

  String _render(String format, AuditResult result) => switch (format) {
    'json' => const JsonReporter().render(result),
    'html' => const HtmlReporter().render(result),
    _ => throw ArgumentError.value(format, 'format'),
  };

  String _normalizeLocaleArg(String value) =>
      normalizeLocale(value) ??
      usageException('Invalid --base-locale "$value".');
}
