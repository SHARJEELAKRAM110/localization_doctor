/// Process exit codes. These values are part of the public contract.
abstract final class ExitCodes {
  /// The audit ran and found no policy violations.
  static const success = 0;

  /// The audit ran and found diagnostics at or above the failure threshold.
  static const violations = 1;

  /// Invalid command-line arguments or configuration.
  static const usage = 2;

  /// The audit could not run (missing project, I/O failure, internal error).
  static const failure = 3;
}
