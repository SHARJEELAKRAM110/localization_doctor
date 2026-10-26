import 'dart:convert';

import '../models/audit_result.dart';

/// Renders an [AuditResult] as pretty-printed JSON (schema version 1).
/// The output never contains colors or log messages.
class JsonReporter {
  const JsonReporter();

  String render(AuditResult result) =>
      '${const JsonEncoder.withIndent('  ').convert(result.toJson())}\n';
}
