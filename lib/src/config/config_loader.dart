import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../discovery/locale_name.dart';
import '../models/diagnostic.dart';
import '../models/translation.dart';
import 'config.dart';

/// Default configuration file name, looked up in the project root.
const defaultConfigFileName = 'localization_doctor.yaml';

/// Report formats understood by the CLI.
const supportedReportFormats = ['terminal', 'json', 'html'];

/// Thrown for invalid configuration. Maps to exit code 2.
class ConfigException implements Exception {
  ConfigException(this.message, {this.path, this.line, this.column});

  final String message;
  final String? path;
  final int? line;
  final int? column;

  @override
  String toString() {
    final where = path == null
        ? ''
        : line == null
        ? '$path: '
        : '$path:$line:$column: ';
    return '$where$message';
  }
}

/// Loads configuration for [projectRoot].
///
/// If [explicitPath] is given the file must exist. Otherwise
/// `localization_doctor.yaml` in the project root is used when present, and
/// defaults are used when it is absent.
DoctorConfig loadConfig(String projectRoot, {String? explicitPath}) {
  final String path;
  if (explicitPath != null) {
    path = explicitPath;
    if (!File(path).existsSync()) {
      throw ConfigException('Configuration file not found.', path: path);
    }
  } else {
    path = p.join(projectRoot, defaultConfigFileName);
    if (!File(path).existsSync()) return const DoctorConfig();
  }
  final String content;
  try {
    content = File(path).readAsStringSync();
  } on FileSystemException catch (e) {
    throw ConfigException(
      'Cannot read configuration: ${e.osError?.message ?? e.message}',
      path: path,
    );
  }
  return parseConfig(content, sourcePath: path);
}

/// Parses and validates configuration YAML.
DoctorConfig parseConfig(String content, {String? sourcePath}) {
  final YamlNode root;
  try {
    root = loadYamlNode(
      content,
      sourceUrl: sourcePath == null ? null : Uri.file(sourcePath),
    );
  } on YamlException catch (e) {
    throw ConfigException(
      'Invalid YAML: ${e.message}',
      path: sourcePath,
      line: e.span == null ? null : e.span!.start.line + 1,
      column: e.span == null ? null : e.span!.start.column + 1,
    );
  }
  if (root is YamlScalar && root.value == null) {
    return DoctorConfig(configPath: sourcePath);
  }
  return _ConfigReader(sourcePath).read(root);
}

class _ConfigReader {
  _ConfigReader(this.sourcePath);

  final String? sourcePath;

  Never _fail(String message, YamlNode node) => throw ConfigException(
    message,
    path: sourcePath,
    line: node.span.start.line + 1,
    column: node.span.start.column + 1,
  );

  YamlMap _map(YamlNode node, String name) {
    if (node is YamlMap) return node;
    if (node is YamlScalar && node.value == null) return YamlMap();
    _fail('"$name" must be a map.', node);
  }

  void _checkKeys(YamlMap map, String section, List<String> allowed) {
    for (final keyNode in map.nodes.keys) {
      final key = (keyNode as YamlNode).value;
      if (key is! String || !allowed.contains(key)) {
        final name = section.isEmpty ? '$key' : '$section.$key';
        final hint = _suggest('$key', allowed);
        _fail(
          'Unknown configuration key "$name".'
          '${hint == null ? '' : ' Did you mean "$hint"?'}'
          ' Allowed: ${allowed.join(', ')}.',
          keyNode,
        );
      }
    }
  }

  YamlNode? _node(YamlMap map, String key) => map.nodes[key];

  String? _string(YamlMap map, String key, String name) {
    final node = _node(map, key);
    if (node == null || (node is YamlScalar && node.value == null)) {
      return null;
    }
    final value = node.value;
    if (value is String && value.trim().isNotEmpty) return value;
    _fail('"$name" must be a non-empty string.', node);
  }

  bool? _bool(YamlMap map, String key, String name) {
    final node = _node(map, key);
    if (node == null) return null;
    final value = node.value;
    if (value is bool) return value;
    _fail('"$name" must be true or false.', node);
  }

  List<String>? _stringList(YamlMap map, String key, String name) {
    final node = _node(map, key);
    if (node == null || (node is YamlScalar && node.value == null)) {
      return null;
    }
    if (node is! YamlList) _fail('"$name" must be a list of strings.', node);
    return [
      for (final item in node.nodes)
        if (item.value is String && (item.value as String).trim().isNotEmpty)
          (item.value as String).trim()
        else
          _fail('"$name" entries must be non-empty strings.', item),
    ];
  }

  List<String>? _localeList(YamlMap map, String key, String name) {
    final values = _stringList(map, key, name);
    if (values == null) return null;
    final node = _node(map, key)! as YamlList;
    return [
      for (var i = 0; i < values.length; i++)
        normalizeLocale(values[i]) ??
            _fail(
              '"${values[i]}" in "$name" is not a valid locale.',
              node.nodes[i],
            ),
    ];
  }

  String? _relativePath(String value, YamlNode node, String name) {
    if (p.isAbsolute(value) || p.posix.isAbsolute(value)) {
      _fail('"$name" must be relative to the project root.', node);
    }
    final normalized = p.posix.normalize(value.replaceAll(r'\', '/'));
    if (normalized == '..' || normalized.startsWith('../')) {
      _fail('"$name" must stay inside the project root.', node);
    }
    return normalized;
  }

  DoctorConfig read(YamlNode rootNode) {
    final root = _map(rootNode, 'configuration');
    _checkKeys(root, '', [
      'base_locale',
      'fail_on',
      'localization',
      'source',
      'checks',
      'ignore',
      'severity',
      'reports',
    ]);

    String? baseLocale;
    final baseNode = _node(root, 'base_locale');
    final baseText = _string(root, 'base_locale', 'base_locale');
    if (baseText != null) {
      baseLocale =
          normalizeLocale(baseText) ??
          _fail('"base_locale" is not a valid locale: "$baseText".', baseNode!);
    }

    var failOn = Severity.error;
    final failOnText = _string(root, 'fail_on', 'fail_on');
    if (failOnText != null) {
      failOn =
          Severity.tryParse(failOnText) ??
          _fail(
            '"fail_on" must be one of error, warning, info.',
            _node(root, 'fail_on')!,
          );
    }

    // localization
    final loc = _map(_node(root, 'localization') ?? YamlMap(), 'localization');
    _checkKeys(loc, 'localization', [
      'directories',
      'formats',
      'required_locales',
      'optional_locales',
      'fail_on_optional_locales',
      'locale_mappings',
      'key_separator',
      'json_placeholder_pattern',
      'arb_use_escaping',
      'arb_relax_syntax',
    ]);
    final dirValues = _stringList(
      loc,
      'directories',
      'localization.directories',
    );
    final directories = dirValues == null
        ? null
        : [
            for (var i = 0; i < dirValues.length; i++)
              _relativePath(
                dirValues[i],
                (_node(loc, 'directories')! as YamlList).nodes[i],
                'localization.directories',
              )!,
          ];

    var formats = const {TranslationFormat.arb, TranslationFormat.json};
    final formatValues = _stringList(loc, 'formats', 'localization.formats');
    if (formatValues != null) {
      if (formatValues.isEmpty) {
        _fail(
          '"localization.formats" must not be empty.',
          _node(loc, 'formats')!,
        );
      }
      formats = {
        for (final f in formatValues)
          TranslationFormat.tryParse(f) ??
              _fail(
                'Unsupported format "$f". Supported: arb, json.',
                _node(loc, 'formats')!,
              ),
      };
    }

    final required =
        _localeList(loc, 'required_locales', 'localization.required_locales') ??
        const [];
    final optional =
        _localeList(loc, 'optional_locales', 'localization.optional_locales') ??
        const [];
    final both = required.toSet().intersection(optional.toSet());
    if (both.isNotEmpty) {
      _fail(
        'Locales cannot be both required and optional: ${both.join(', ')}.',
        _node(loc, 'optional_locales')!,
      );
    }

    final mappings = <String, String>{};
    final mappingNode = _node(loc, 'locale_mappings');
    if (mappingNode != null) {
      final map = _map(mappingNode, 'localization.locale_mappings');
      for (final entry in map.nodes.entries) {
        final keyNode = entry.key as YamlNode;
        final file = keyNode.value;
        final locale = entry.value.value;
        if (file is! String || locale is! String) {
          _fail(
            '"localization.locale_mappings" must map file paths to locales.',
            keyNode,
          );
        }
        final normalizedLocale =
            normalizeLocale(locale) ??
            _fail('"$locale" is not a valid locale.', entry.value);
        mappings[_relativePath(
              file,
              keyNode,
              'localization.locale_mappings',
            )!] =
            normalizedLocale;
      }
    }

    final separator =
        _string(loc, 'key_separator', 'localization.key_separator') ?? '.';

    final pattern =
        _string(
          loc,
          'json_placeholder_pattern',
          'localization.json_placeholder_pattern',
        ) ??
        defaultJsonPlaceholderPattern;
    try {
      final regex = RegExp(pattern);
      if (regex.hasMatch('')) {
        _fail(
          '"localization.json_placeholder_pattern" must not match empty text.',
          _node(loc, 'json_placeholder_pattern')!,
        );
      }
    } on FormatException catch (e) {
      _fail(
        'Invalid regular expression in '
        '"localization.json_placeholder_pattern": ${e.message}',
        _node(loc, 'json_placeholder_pattern')!,
      );
    }

    // source
    final src = _map(_node(root, 'source') ?? YamlMap(), 'source');
    _checkKeys(src, 'source', [
      'directories',
      'exclude',
      'localization_classes',
      'accessors',
      'json_lookup_functions',
      'key_classes',
    ]);
    final srcDirs = _stringList(src, 'directories', 'source.directories');
    final identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');
    final classes = _stringList(
      src,
      'localization_classes',
      'source.localization_classes',
    );
    for (final c in classes ?? const <String>[]) {
      if (!identifier.hasMatch(c)) {
        _fail(
          '"$c" in "source.localization_classes" is not a Dart identifier.',
          _node(src, 'localization_classes')!,
        );
      }
    }
    final lookups = _stringList(
      src,
      'json_lookup_functions',
      'source.json_lookup_functions',
    );
    for (final f in lookups ?? const <String>[]) {
      if (!identifier.hasMatch(f)) {
        _fail(
          '"$f" in "source.json_lookup_functions" is not a Dart identifier.',
          _node(src, 'json_lookup_functions')!,
        );
      }
    }
    final keyClasses = _stringList(src, 'key_classes', 'source.key_classes');
    for (final c in keyClasses ?? const <String>[]) {
      if (!identifier.hasMatch(c)) {
        _fail(
          '"$c" in "source.key_classes" is not a Dart identifier.',
          _node(src, 'key_classes')!,
        );
      }
    }

    // checks
    final checksMap = _map(_node(root, 'checks') ?? YamlMap(), 'checks');
    _checkKeys(checksMap, 'checks', ChecksConfig.names);
    bool check(String name) => _bool(checksMap, name, 'checks.$name') ?? true;
    final checks = ChecksConfig(
      missingKeys: check('missing_keys'),
      extraKeys: check('extra_keys'),
      unusedKeys: check('unused_keys'),
      duplicateKeys: check('duplicate_keys'),
      placeholderMismatches: check('placeholder_mismatches'),
      emptyValues: check('empty_values'),
      messageSyntax: check('message_syntax'),
      configuration: check('configuration'),
    );

    // ignore
    final ignoreMap = _map(_node(root, 'ignore') ?? YamlMap(), 'ignore');
    _checkKeys(ignoreMap, 'ignore', ['keys', 'unused_keys', 'diagnostics']);
    final rules = <IgnoreRule>[];
    final rulesNode = _node(ignoreMap, 'diagnostics');
    if (rulesNode != null &&
        !(rulesNode is YamlScalar && rulesNode.value == null)) {
      if (rulesNode is! YamlList) {
        _fail('"ignore.diagnostics" must be a list.', rulesNode);
      }
      for (final item in rulesNode.nodes) {
        final rule = _map(item, 'ignore.diagnostics[]');
        _checkKeys(rule, 'ignore.diagnostics[]', [
          'code',
          'key',
          'locale',
          'path',
        ]);
        final codeText = _string(rule, 'code', 'ignore.diagnostics[].code');
        DiagnosticCode? code;
        if (codeText != null) {
          code =
              DiagnosticCode.tryParse(codeText) ??
              _fail(
                'Unknown diagnostic code "$codeText".',
                _node(rule, 'code')!,
              );
          if (!code.isSuppressible) {
            _fail(
              '$codeText cannot be ignored: invalid translation files are '
              'always reported.',
              _node(rule, 'code')!,
            );
          }
        }
        final keyText = _string(rule, 'key', 'ignore.diagnostics[].key');
        final localeText = _string(
          rule,
          'locale',
          'ignore.diagnostics[].locale',
        );
        final pathText = _string(rule, 'path', 'ignore.diagnostics[].path');
        if (code == null &&
            keyText == null &&
            localeText == null &&
            pathText == null) {
          _fail(
            'An ignore rule must set at least one of code, key, locale, path.',
            item,
          );
        }
        rules.add(
          IgnoreRule(
            code: code,
            key: keyText == null ? null : KeyPattern(keyText),
            locale: localeText == null
                ? null
                : normalizeLocale(localeText) ??
                      _fail(
                        '"$localeText" is not a valid locale.',
                        _node(rule, 'locale')!,
                      ),
            path: pathText?.replaceAll(r'\', '/'),
          ),
        );
      }
    }
    final ignore = IgnoreConfig(
      keys: [
        for (final k
            in _stringList(ignoreMap, 'keys', 'ignore.keys') ??
                const <String>[])
          KeyPattern(k),
      ],
      unusedKeys: [
        for (final k
            in _stringList(ignoreMap, 'unused_keys', 'ignore.unused_keys') ??
                const <String>[])
          KeyPattern(k),
      ],
      rules: rules,
    );

    // severity overrides
    final severityMap = _map(_node(root, 'severity') ?? YamlMap(), 'severity');
    final overrides = <DiagnosticCode, Severity>{};
    for (final entry in severityMap.nodes.entries) {
      final keyNode = entry.key as YamlNode;
      final code = keyNode.value is String
          ? DiagnosticCode.tryParse(keyNode.value as String)
          : null;
      if (code == null) {
        _fail(
          'Unknown diagnostic code "${keyNode.value}" in "severity".',
          keyNode,
        );
      }
      final value = entry.value.value;
      final severity = value is String ? Severity.tryParse(value) : null;
      if (severity == null) {
        _fail(
          'Severity for ${code.id} must be one of error, warning, info.',
          entry.value,
        );
      }
      if (code == DiagnosticCode.invalidFile && severity != Severity.error) {
        _fail(
          'LOC006 (invalid translation file) is always an error.',
          entry.value,
        );
      }
      overrides[code] = severity;
    }

    // reports
    final reports = _map(_node(root, 'reports') ?? YamlMap(), 'reports');
    _checkKeys(reports, 'reports', ['formats', 'output_directory']);
    final reportFormats =
        _stringList(reports, 'formats', 'reports.formats') ??
        const ['terminal'];
    for (final f in reportFormats) {
      if (!supportedReportFormats.contains(f)) {
        _fail(
          'Unsupported report format "$f". Supported: '
          '${supportedReportFormats.join(', ')}.',
          _node(reports, 'formats')!,
        );
      }
    }
    final outputDirNode = _node(reports, 'output_directory');
    final outputDir = _string(
      reports,
      'output_directory',
      'reports.output_directory',
    );

    return DoctorConfig(
      baseLocale: baseLocale,
      directories: directories,
      formats: formats,
      requiredLocales: required,
      optionalLocales: optional,
      failOnOptionalLocales:
          _bool(
            loc,
            'fail_on_optional_locales',
            'localization.fail_on_optional_locales',
          ) ??
          false,
      localeMappings: mappings,
      keySeparator: separator,
      jsonPlaceholderPattern: pattern,
      arbUseEscaping: _bool(
        loc,
        'arb_use_escaping',
        'localization.arb_use_escaping',
      ),
      arbRelaxSyntax: _bool(
        loc,
        'arb_relax_syntax',
        'localization.arb_relax_syntax',
      ),
      explicitSourceDirectories: srcDirs != null,
      sourceDirectories: srcDirs == null
          ? const ['lib']
          : [
              for (var i = 0; i < srcDirs.length; i++)
                _relativePath(
                  srcDirs[i],
                  (_node(src, 'directories')! as YamlList).nodes[i],
                  'source.directories',
                )!,
            ],
      sourceExclude: [
        for (final e
            in _stringList(src, 'exclude', 'source.exclude') ??
                const <String>[])
          e.replaceAll(r'\', '/'),
      ],
      localizationClasses: classes,
      accessors: [
        for (final a
            in _stringList(src, 'accessors', 'source.accessors') ??
                const <String>[])
          a.replaceAll(RegExp(r'\s+'), ''),
      ],
      jsonLookupFunctions: lookups ?? defaultJsonLookupFunctions,
      keyClasses: keyClasses ?? defaultKeyClasses,
      checks: checks,
      ignore: ignore,
      severityOverrides: overrides,
      failOn: failOn,
      reportFormats: reportFormats.toSet().toList(),
      outputDirectory: outputDir == null
          ? null
          : (p.isAbsolute(outputDir)
                ? outputDir
                : _relativePath(
                    outputDir,
                    outputDirNode!,
                    'reports.output_directory',
                  )),
      configPath: sourcePath,
    );
  }
}

String? _suggest(String value, List<String> options) {
  String? best;
  var bestDistance = 3;
  for (final option in options) {
    final d = _levenshtein(value, option);
    if (d < bestDistance) {
      bestDistance = d;
      best = option;
    }
  }
  return best;
}

int _levenshtein(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[b.length];
}
