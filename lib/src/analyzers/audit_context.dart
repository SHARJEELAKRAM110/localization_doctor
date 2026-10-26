import '../config/config.dart';
import '../flutter/project_info.dart';
import '../models/translation.dart';

/// Shared, read-only inputs for all analyzers.
class AuditContext {
  AuditContext({
    required this.root,
    required this.config,
    required this.project,
    required this.bundles,
  }) : placeholderPattern = RegExp(config.jsonPlaceholderPattern);

  /// Absolute, normalized project root.
  final String root;
  final DoctorConfig config;
  final ProjectInfo project;
  final List<TranslationBundle> bundles;
  final RegExp placeholderPattern;

  bool get useEscaping => config.arbUseEscaping ?? project.l10n.useEscaping;

  bool get relaxSyntax => config.arbRelaxSyntax ?? project.l10n.relaxSyntax;

  /// Generated localization class names used for source scanning.
  List<String> get localizationClasses =>
      config.localizationClasses ?? [project.l10n.outputClass];

  bool isOptional(String locale) => config.optionalLocales.contains(locale);

  /// Whether [key] is excluded from all key-level checks.
  bool isIgnoredKey(String key) =>
      config.ignore.keys.any((pattern) => pattern.matches(key));
}
