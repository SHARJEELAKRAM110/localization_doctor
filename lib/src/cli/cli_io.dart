import 'dart:io';

/// Output streams and terminal capabilities, injectable for tests.
class CliIo {
  CliIo({required this.out, required this.err, required this.supportsColor});

  /// Uses the process streams. Colors are enabled only when stdout is a
  /// terminal that supports ANSI escapes and `NO_COLOR` is not set
  /// (https://no-color.org).
  factory CliIo.process() {
    final noColor = Platform.environment['NO_COLOR']?.isNotEmpty ?? false;
    final color = !noColor && stdout.hasTerminal && stdout.supportsAnsiEscapes;
    return CliIo(out: stdout, err: stderr, supportsColor: color);
  }

  final StringSink out;
  final StringSink err;
  final bool supportsColor;
}
