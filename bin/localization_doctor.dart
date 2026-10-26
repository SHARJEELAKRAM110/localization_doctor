import 'dart:io';

import 'package:localization_doctor/src/cli/command_runner.dart';

Future<void> main(List<String> arguments) async {
  final code = await runCli(arguments);
  await Future.wait([stdout.flush(), stderr.flush()]);
  exit(code);
}
