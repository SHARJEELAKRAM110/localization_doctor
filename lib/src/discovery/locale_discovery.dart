import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../flutter/project_info.dart';
import '../models/diagnostic.dart';
import '../models/translation.dart';
import 'locale_name.dart';

/// A translation file found on disk, before parsing.
class DiscoveredFile {
  const DiscoveredFile({
    required this.path,
    required this.absolutePath,
    required this.format,
    required this.bundleId,
    required this.directory,
    this.locale,
  });

  /// Project-relative path with forward slashes.
  final String path;
  final String absolutePath;
  final TranslationFormat format;
  final String bundleId;
  final String directory;

  /// Locale from configuration or the file name. `null` for ARB files that
  /// must be resolved through `@@locale`.
  final String? locale;
}

class DiscoveryResult {
  DiscoveryResult(this.files, this.directories, this.diagnostics, this.skipped);

  /// Files sorted by path.
  final List<DiscoveredFile> files;

  /// Directories that were searched (project-relative).
  final List<String> directories;
  final List<Diagnostic> diagnostics;

  /// Files that were not treated as translations, with the reason.
  final List<String> skipped;
}

/// Converts an absolute path below [root] to a project-relative path with
/// forward slashes.
String relativePath(String absolute, String root) =>
    p.relative(absolute, from: root).replaceAll(r'\', '/');

/// Finds translation files according to [config].
///
/// Directories are searched recursively. Symbolic links are never followed,
/// so the audit cannot escape the project root through a link.
DiscoveryResult discoverTranslationFiles(
  String root,
  DoctorConfig config,
  ProjectInfo project,
) {
  final diagnostics = <Diagnostic>[];
  final skipped = <String>[];
  final explicit = config.directories != null;
  final candidates = <String>[
    ...?config.directories,
    if (!explicit) ...[
      if (project.l10n.exists) project.l10n.arbDir,
      ...defaultLocalizationDirectories,
    ],
  ];

  final directories = <String>[];
  for (final dir in candidates) {
    if (directories.contains(dir)) continue;
    final absolute = p.normalize(p.join(root, dir));
    if (!p.isWithin(root, absolute) && !p.equals(root, absolute)) {
      diagnostics.add(
        Diagnostic(
          code: DiagnosticCode.configuration,
          severity: Severity.error,
          message: 'Localization directory "$dir" is outside the project.',
          suggestion: 'Use a directory inside the project root.',
        ),
      );
      continue;
    }
    if (!Directory(absolute).existsSync()) {
      if (explicit) {
        diagnostics.add(
          Diagnostic(
            code: DiagnosticCode.configuration,
            severity: Severity.error,
            message: 'Configured localization directory "$dir" does not exist.',
            suggestion:
                'Fix "localization.directories" in the configuration file.',
          ),
        );
      }
      continue;
    }
    directories.add(dir);
  }

  final extensions = {for (final f in config.formats) '.${f.extension}': f};
  final seen = <String>{};
  final files = <DiscoveredFile>[];

  for (final dir in directories) {
    final absoluteDir = p.normalize(p.join(root, dir));
    final List<FileSystemEntity> entities;
    try {
      entities = Directory(
        absoluteDir,
      ).listSync(recursive: true, followLinks: false);
    } on FileSystemException catch (e) {
      diagnostics.add(
        Diagnostic(
          code: DiagnosticCode.configuration,
          severity: Severity.error,
          message:
              'Cannot read directory "$dir": '
              '${e.osError?.message ?? e.message}.',
          suggestion: 'Check the directory permissions.',
        ),
      );
      continue;
    }
    for (final entity in entities) {
      final rel = relativePath(entity.path, root);
      if (rel.split('/').any((s) => s.startsWith('.') && s.length > 1)) {
        continue;
      }
      final format = extensions[p.extension(entity.path).toLowerCase()];
      if (format == null) continue;
      if (entity is Link) {
        skipped.add('$rel (symbolic link, not followed)');
        continue;
      }
      if (entity is! File || !seen.add(rel)) continue;

      final fileDir = p.posix.dirname(rel);
      final stem = p.basenameWithoutExtension(entity.path);
      final mapped = config.localeMappings[rel];
      String prefix;
      String? locale;
      if (mapped != null) {
        locale = mapped;
        prefix = detectLocaleFromFileName(stem)?.prefix ?? '';
      } else {
        final detected = detectLocaleFromFileName(stem);
        if (detected == null) {
          if (format == TranslationFormat.arb) {
            // The locale may come from "@@locale"; group by the full stem's
            // leading word so `app.arb` style files stay together.
            prefix = '';
          } else {
            skipped.add(
              '$rel (no locale in file name; add it to '
              'localization.locale_mappings)',
            );
            continue;
          }
        } else {
          prefix = detected.prefix;
          locale = detected.locale;
        }
      }
      files.add(
        DiscoveredFile(
          path: rel,
          absolutePath: entity.path,
          format: format,
          directory: fileDir,
          bundleId: '$fileDir/$prefix*.${format.extension}',
          locale: locale,
        ),
      );
    }
  }

  for (final mappedPath in config.localeMappings.keys) {
    if (!seen.contains(mappedPath)) {
      diagnostics.add(
        Diagnostic(
          code: DiagnosticCode.configuration,
          severity: Severity.warning,
          message:
              'locale_mappings refers to "$mappedPath", which was not found '
              'in the localization directories.',
          suggestion:
              'Fix the path or add its directory to '
              '"localization.directories".',
        ),
      );
    }
  }

  files.sort((a, b) => a.path.compareTo(b.path));
  skipped.sort();
  return DiscoveryResult(files, directories, diagnostics, skipped);
}
