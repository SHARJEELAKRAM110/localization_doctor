import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../config/config.dart';
import '../../config/config_loader.dart';
import '../../discovery/locale_discovery.dart';
import '../../flutter/project_info.dart';
import '../../models/translation.dart';
import '../cli_io.dart';
import '../exit_codes.dart';

class InitCommand extends Command<int> {
  InitCommand(this.io) {
    argParser.addOption(
      'path',
      abbr: 'p',
      help: 'Project directory in which to create the configuration.',
      defaultsTo: '.',
    );
  }

  final CliIo io;

  @override
  void printUsage() => io.out.writeln(usage);

  @override
  String get name => 'init';

  @override
  String get description =>
      'Create a starter $defaultConfigFileName. Never overwrites an '
      'existing file.';

  @override
  Future<int> run() async {
    final root = argResults!['path'] as String;
    if (!Directory(root).existsSync()) {
      io.err.writeln('Error: project directory "$root" does not exist.');
      return ExitCodes.failure;
    }
    final file = File(p.join(root, defaultConfigFileName));
    if (file.existsSync()) {
      io.err.writeln(
        '${file.path} already exists and was not modified. Delete it first '
        'to generate a new one.',
      );
      return ExitCodes.usage;
    }
    final absoluteRoot = p.normalize(p.absolute(root));
    final project = ProjectInfo.read(absoluteRoot);
    final discovery = discoverTranslationFiles(
      absoluteRoot,
      const DoctorConfig(),
      project,
    );
    final content = buildStarterConfig(project, discovery);
    try {
      file.writeAsStringSync(content);
    } on FileSystemException catch (e) {
      io.err.writeln(
        'Error: cannot write ${file.path}: ${e.osError?.message ?? e.message}',
      );
      return ExitCodes.failure;
    }
    io.out.writeln('Created ${file.path}');
    if (discovery.files.isEmpty) {
      io.out.writeln(
        'No translation files were detected; edit localization.directories '
        'before running the audit.',
      );
    }
    return ExitCodes.success;
  }
}

/// Builds a commented starter configuration from what was detected.
String buildStarterConfig(ProjectInfo project, DiscoveryResult discovery) {
  final locales = <String>{
    for (final f in discovery.files)
      if (f.locale != null) f.locale!,
  }.toList()..sort();
  final templateLocale = discovery.files
      .where(
        (f) =>
            f.path == '${project.l10n.arbDir}/${project.l10n.templateArbFile}',
      )
      .map((f) => f.locale)
      .firstOrNull;
  final base =
      templateLocale ??
      (locales.contains('en')
          ? 'en'
          : (locales.isEmpty ? 'en' : locales.first));
  final directories = discovery.directories.isEmpty
      ? ['lib/l10n']
      : discovery.directories;
  final formats = {for (final f in discovery.files) f.format.name}.toList()
    ..sort();
  final hasJson = formats.contains(TranslationFormat.json.name);

  String list(Iterable<String> items, String indent) =>
      items.map((i) => '$indent- $i').join('\n');

  final required = locales.isEmpty ? [base] : locales;
  return '''
# Localization Doctor configuration.
# Reference: https://pub.dev/packages/localization_doctor
# Command-line flags override values in this file.

# Locale every other locale is compared with.
base_locale: $base

# Lowest severity that fails the audit: error | warning | info.
# `--strict` lowers it to warning.
fail_on: error

localization:
  directories:
${list(directories, '    ')}
  formats:
${list(formats.isEmpty ? ['arb', 'json'] : formats, '    ')}
  # Locales that must be complete. Missing keys here are errors.
  required_locales:
${list(required, '    ')}
  # Locales that may be incomplete. Their missing keys are reported as info.
  optional_locales: []
${hasJson ? '''  # Regular expression for JSON placeholders; group 1 is the name.
  json_placeholder_pattern: '$defaultJsonPlaceholderPattern'
''' : ''}
source:
  directories:
    - lib
  exclude:
    - lib/generated/**
  # Generated localizations class (from l10n.yaml `output-class`).
  localization_classes:
    - ${project.l10n.outputClass}
  # Extra expressions that return the localizations object, for example an
  # extension getter such as `context.l10n`.
  accessors: []

checks:
  missing_keys: true
  extra_keys: true
  unused_keys: true
  duplicate_keys: true
  placeholder_mismatches: true
  empty_values: true
  message_syntax: true
  configuration: true

ignore:
  # Excluded from every key-level check and from coverage.
  keys: []
  # Never reported as unused (for example keys built at runtime).
  unused_keys: []
  # Known exceptions, e.g. {code: LOC008, locale: fr, key: legacy.*}
  diagnostics: []

reports:
  formats:
    - terminal
''';
}
