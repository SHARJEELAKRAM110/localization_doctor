import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Settings read from `l10n.yaml`, with Flutter's documented defaults.
class L10nSettings {
  const L10nSettings({
    required this.exists,
    this.arbDir = 'lib/l10n',
    this.templateArbFile = 'app_en.arb',
    this.outputDir,
    this.outputLocalizationFile = 'app_localizations.dart',
    this.outputClass = 'AppLocalizations',
    this.useEscaping = false,
    this.relaxSyntax = false,
    this.syntheticPackage,
    this.error,
  });

  /// Whether `l10n.yaml` exists.
  final bool exists;
  final String arbDir;
  final String templateArbFile;

  /// Explicit `output-dir`; generated files go to [arbDir] when unset.
  final String? outputDir;
  final String outputLocalizationFile;
  final String outputClass;
  final bool useEscaping;
  final bool relaxSyntax;

  /// Value of the removed `synthetic-package` option, if present.
  final bool? syntheticPackage;

  /// Problem reading the file, if any.
  final String? error;

  /// Directory that receives generated code.
  String get effectiveOutputDir => outputDir ?? arbDir;
}

/// Facts about the audited project gathered from `pubspec.yaml` and
/// `l10n.yaml`. Nothing here modifies the project.
class ProjectInfo {
  const ProjectInfo({
    required this.hasPubspec,
    required this.l10n,
    this.pubspecError,
    this.isFlutter = false,
    this.generateFlag = false,
    this.dependencies = const {},
    this.assets = const [],
  });

  final bool hasPubspec;
  final String? pubspecError;
  final bool isFlutter;

  /// Value of `flutter: generate:`.
  final bool generateFlag;

  /// Names in `dependencies` and `dev_dependencies`.
  final Set<String> dependencies;

  /// Entries of `flutter: assets:` (strings only), with forward slashes.
  final List<String> assets;
  final L10nSettings l10n;

  static ProjectInfo read(String root) {
    final l10n = _readL10n(root);
    final pubspecFile = File(p.join(root, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      return ProjectInfo(hasPubspec: false, l10n: l10n);
    }
    final Object? doc;
    try {
      doc = loadYaml(pubspecFile.readAsStringSync());
    } on Exception catch (e) {
      return ProjectInfo(
        hasPubspec: true,
        pubspecError: e is YamlException ? e.message : '$e',
        l10n: l10n,
      );
    }
    if (doc is! YamlMap) {
      return ProjectInfo(
        hasPubspec: true,
        pubspecError: 'pubspec.yaml does not contain a map',
        l10n: l10n,
      );
    }
    final deps = <String>{};
    for (final section in ['dependencies', 'dev_dependencies']) {
      final value = doc[section];
      if (value is YamlMap) deps.addAll(value.keys.whereType<String>());
    }
    final flutter = doc['flutter'];
    var generate = false;
    final assets = <String>[];
    if (flutter is YamlMap) {
      generate = flutter['generate'] == true;
      final assetList = flutter['assets'];
      if (assetList is YamlList) {
        for (final asset in assetList) {
          if (asset is String) {
            assets.add(asset.replaceAll(r'\', '/'));
          } else if (asset is YamlMap && asset['path'] is String) {
            assets.add((asset['path'] as String).replaceAll(r'\', '/'));
          }
        }
      }
    }
    return ProjectInfo(
      hasPubspec: true,
      isFlutter: deps.contains('flutter') || flutter is YamlMap,
      generateFlag: generate,
      dependencies: deps,
      assets: assets,
      l10n: l10n,
    );
  }

  static L10nSettings _readL10n(String root) {
    final file = File(p.join(root, 'l10n.yaml'));
    if (!file.existsSync()) return const L10nSettings(exists: false);
    final Object? doc;
    try {
      doc = loadYaml(file.readAsStringSync());
    } on Exception catch (e) {
      return L10nSettings(
        exists: true,
        error: e is YamlException ? e.message : '$e',
      );
    }
    if (doc == null) return const L10nSettings(exists: true);
    if (doc is! YamlMap) {
      return const L10nSettings(
        exists: true,
        error: 'l10n.yaml does not contain a map',
      );
    }
    final map = doc;
    String? str(String key) {
      final value = map[key];
      return value is String ? value.replaceAll(r'\', '/') : null;
    }

    bool? flag(String key) {
      final value = map[key];
      return value is bool ? value : null;
    }

    String clean(String path) {
      final normalized = p.posix.normalize(path);
      return normalized.startsWith('./') ? normalized.substring(2) : normalized;
    }

    final arbDir = str('arb-dir');
    final outputDir = str('output-dir');
    return L10nSettings(
      exists: true,
      arbDir: arbDir == null ? 'lib/l10n' : clean(arbDir),
      templateArbFile: str('template-arb-file') ?? 'app_en.arb',
      outputDir: outputDir == null ? null : clean(outputDir),
      outputLocalizationFile:
          str('output-localization-file') ?? 'app_localizations.dart',
      outputClass: str('output-class') ?? 'AppLocalizations',
      useEscaping: flag('use-escaping') ?? false,
      relaxSyntax: flag('relax-syntax') ?? false,
      syntheticPackage: flag('synthetic-package'),
    );
  }
}
