/// Audits Flutter and Dart localization files.
///
/// Most users run the `localization_doctor` command-line tool. This library
/// exposes the same engine for programmatic use:
///
/// ```dart
/// import 'package:localization_doctor/localization_doctor.dart';
///
/// void main() {
///   final config = loadConfig('.');
///   final result = LocalizationAuditor(projectPath: '.', config: config).run();
///   print(const JsonReporter().render(result));
/// }
/// ```
library;

export 'src/auditor.dart' show AuditException, LocalizationAuditor;
export 'src/cli/exit_codes.dart' show ExitCodes;
export 'src/config/config.dart'
    show ChecksConfig, DoctorConfig, IgnoreConfig, IgnoreRule, KeyPattern;
export 'src/config/config_loader.dart'
    show ConfigException, defaultConfigFileName, loadConfig, parseConfig;
export 'src/models/audit_result.dart'
    show AuditResult, BundleSummary, LocaleCoverage;
export 'src/models/diagnostic.dart'
    show Confidence, Diagnostic, DiagnosticCode, Severity, SourceLocation;
export 'src/models/translation.dart' show TranslationFormat;
export 'src/reporters/html_reporter.dart' show HtmlReporter, escapeHtml;
export 'src/reporters/json_reporter.dart' show JsonReporter;
export 'src/reporters/terminal_reporter.dart' show TerminalReporter, Verbosity;
export 'src/version.dart' show packageVersion;
