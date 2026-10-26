import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../config/config_loader.dart';
import '../version.dart';
import 'cli_io.dart';
import 'commands/audit_command.dart';
import 'commands/init_command.dart';
import 'exit_codes.dart';

const executableName = 'localization_doctor';

class DoctorCommandRunner extends CommandRunner<int> {
  DoctorCommandRunner(this.io)
    : super(
        executableName,
        'Audit Flutter and Dart localization files for missing, unused, '
        'duplicate and inconsistent translations.\n\n'
        'Running without a command is the same as running `audit`.\n\n'
        'Exit codes: 0 passed, 1 policy violations, 2 invalid arguments or '
        'configuration, 3 audit could not run.',
      ) {
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the tool version.',
    );
    addCommand(AuditCommand(io));
    addCommand(InitCommand(io));
  }

  final CliIo io;

  @override
  void printUsage() => io.out.writeln(usage);

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults['version'] as bool) {
      io.out.writeln('$executableName $packageVersion');
      return ExitCodes.success;
    }
    return super.runCommand(topLevelResults);
  }
}

/// Runs the CLI and returns the process exit code. Never throws.
Future<int> runCli(List<String> arguments, {CliIo? io}) async {
  final cliIo = io ?? CliIo.process();
  final args = [...arguments];
  final first = args.isEmpty ? null : args.first;
  final isTopLevelOnly =
      first == '--version' ||
      first == '--help' ||
      first == '-h' ||
      first == 'help';
  if (first == null || (first.startsWith('-') && !isTopLevelOnly)) {
    args.insert(0, 'audit');
  }
  final runner = DoctorCommandRunner(cliIo);
  try {
    final result = await runner.run(args);
    return result ?? ExitCodes.success;
  } on UsageException catch (e) {
    cliIo.err
      ..writeln('Error: ${e.message}')
      ..writeln()
      ..writeln(e.usage);
    return ExitCodes.usage;
  } on ConfigException catch (e) {
    cliIo.err.writeln('Configuration error: $e');
    return ExitCodes.usage;
  } on Object catch (e, stack) {
    cliIo.err
      ..writeln('Unexpected error: $e')
      ..writeln(stack);
    return ExitCodes.failure;
  }
}
