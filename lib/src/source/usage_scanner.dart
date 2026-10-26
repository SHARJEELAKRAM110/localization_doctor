import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../discovery/locale_discovery.dart';
import '../discovery/locale_name.dart';
import '../models/diagnostic.dart';

/// A JSON lookup whose key is not a plain string literal, e.g.
/// `'errors.$code'.tr()` or `tr(key)`.
class DynamicLookup {
  const DynamicLookup(this.location, this.prefix);

  final SourceLocation location;

  /// Literal text before the first interpolation, or empty when nothing is
  /// known about the key.
  final String prefix;
}

/// A `supportedLocales: [...]` list written with literal `Locale` values.
class SupportedLocalesDeclaration {
  const SupportedLocalesDeclaration(this.location, this.locales);

  final SourceLocation location;
  final List<String> locales;
}

/// Everything the scanner learned about key usage. Paths are
/// project-relative.
class UsageScanResult {
  final generatedMembers = <String, List<SourceLocation>>{};
  final identifiers = <String>{};
  final literalLookups = <String, List<SourceLocation>>{};
  final stringLiterals = <String>{};
  final dynamicLookups = <DynamicLookup>[];
  final supportedLocales = <SupportedLocalesDeclaration>[];
  final diagnostics = <Diagnostic>[];
  final scannedFiles = <String>[];
  final skippedGeneratedFiles = <String>[];

  /// String constants of key classes such as easy_localization's generated
  /// `LocaleKeys`: class name -> constant name -> key.
  final keyConstants = <String, Map<String, String>>{};

  /// Files that declare a key class.
  final keyClassFiles = <String>[];
}

/// Options for [scanSourceUsage].
class UsageScanOptions {
  const UsageScanOptions({
    required this.sourceDirectories,
    required this.exclude,
    required this.localizationClasses,
    required this.accessors,
    required this.jsonLookupFunctions,
    this.keyClasses = const [],
    this.reportMissingDirectories = true,
  });

  final List<String> sourceDirectories;

  /// Glob patterns relative to the project root.
  final List<String> exclude;
  final List<String> localizationClasses;
  final List<String> accessors;
  final List<String> jsonLookupFunctions;

  /// Classes whose `static const` string fields are translation keys, such
  /// as easy_localization's generated `LocaleKeys`.
  final List<String> keyClasses;
  final bool reportMissingDirectories;
}

const _alwaysSkippedDirectories = {'build', '.dart_tool', '.git', '.pub-cache'};

/// Statically scans Dart files under the source directories. Files are
/// parsed with `package:analyzer` (no resolution, nothing is executed).
UsageScanResult scanSourceUsage(String root, UsageScanOptions options) {
  final result = UsageScanResult();
  final globs = [
    for (final pattern in [...defaultSourceExcludes, ...options.exclude])
      Glob(pattern, context: p.posix),
  ];
  final generatedClassPattern = options.localizationClasses.isEmpty
      ? null
      : RegExp(
          r'\bclass\s+\w+\s+extends\s+(?:'
          '${options.localizationClasses.map(RegExp.escape).join('|')}'
          r')\b|\babstract\s+class\s+(?:'
          '${options.localizationClasses.map(RegExp.escape).join('|')}'
          r')\b',
        );

  final files = <String>{};
  // Excluded files are not scanned for usage, but may declare key classes
  // (easy_localization writes `LocaleKeys` to a `*.g.dart` file).
  final excludedFiles = <String>{};
  for (final dir in options.sourceDirectories) {
    final absolute = p.normalize(p.join(root, dir));
    if (!p.isWithin(root, absolute) && !p.equals(root, absolute)) continue;
    final directory = Directory(absolute);
    if (!directory.existsSync()) {
      if (!options.reportMissingDirectories) continue;
      result.diagnostics.add(
        Diagnostic(
          code: DiagnosticCode.configuration,
          severity: Severity.warning,
          message:
              'Source directory "$dir" does not exist; no Dart files '
              'were scanned there.',
          suggestion: 'Fix "source.directories" in the configuration file.',
        ),
      );
      continue;
    }
    try {
      for (final entity in directory.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final rel = relativePath(entity.path, root);
        final segments = rel.split('/');
        if (segments.any(
          (s) =>
              _alwaysSkippedDirectories.contains(s) ||
              (s.startsWith('.') && s.length > 1),
        )) {
          continue;
        }
        if (globs.any((g) => g.matches(rel))) {
          excludedFiles.add(rel);
          continue;
        }
        files.add(rel);
      }
    } on FileSystemException catch (e) {
      result.diagnostics.add(
        Diagnostic(
          code: DiagnosticCode.configuration,
          severity: Severity.error,
          message:
              'Cannot read source directory "$dir": '
              '${e.osError?.message ?? e.message}.',
        ),
      );
    }
  }

  final keyClasses = options.keyClasses.toSet();
  final keyClassPattern = keyClasses.isEmpty
      ? null
      : RegExp(
          r'\bclass\s+(?:'
          '${keyClasses.map(RegExp.escape).join('|')}'
          r')\b',
        );
  final contents = <String, String>{};
  if (keyClassPattern != null) {
    for (final rel in [...files, ...excludedFiles]..sort()) {
      final String content;
      try {
        content = File(p.join(root, rel)).readAsStringSync();
      } on Exception {
        continue; // Reported below for scanned files.
      }
      if (files.contains(rel)) contents[rel] = content;
      if (!keyClassPattern.hasMatch(content)) continue;
      final unit = parseString(
        content: content,
        path: p.join(root, rel),
        throwIfDiagnostics: false,
      ).unit;
      unit.accept(_KeyClassVisitor(keyClasses, result.keyConstants));
      result.keyClassFiles.add(rel);
    }
  }

  final sorted = files.toList()..sort();
  for (final rel in sorted) {
    // A key class declares every key as a string literal; scanning it would
    // make every key look possibly used.
    if (result.keyClassFiles.contains(rel)) {
      result.skippedGeneratedFiles.add(rel);
      continue;
    }
    final String content;
    try {
      content = contents[rel] ?? File(p.join(root, rel)).readAsStringSync();
    } on FileSystemException catch (e) {
      result.diagnostics.add(
        Diagnostic(
          code: DiagnosticCode.configuration,
          severity: Severity.warning,
          message: 'Cannot read "$rel": ${e.osError?.message ?? e.message}.',
          location: SourceLocation(rel),
        ),
      );
      continue;
    } on FormatException {
      result.diagnostics.add(
        Diagnostic(
          code: DiagnosticCode.configuration,
          severity: Severity.warning,
          message: '"$rel" is not valid UTF-8 and was not scanned.',
          location: SourceLocation(rel),
        ),
      );
      continue;
    }
    // Generated localization classes declare every key; scanning them would
    // make every key look used.
    if (generatedClassPattern != null &&
        generatedClassPattern.hasMatch(content)) {
      result.skippedGeneratedFiles.add(rel);
      continue;
    }
    final unit = parseString(
      content: content,
      path: p.join(root, rel),
      throwIfDiagnostics: false,
    ).unit;
    result.scannedFiles.add(rel);
    final tracked = <String>{};
    final classes = options.localizationClasses.toSet();
    unit.accept(_TrackingVisitor(classes, options.accessors.toSet(), tracked));
    unit.accept(
      _UsageVisitor(
        path: rel,
        lineInfo: unit.lineInfo,
        classes: classes,
        accessors: options.accessors.toSet(),
        lookups: options.jsonLookupFunctions.toSet(),
        keyConstants: result.keyConstants,
        tracked: tracked,
        result: result,
      ),
    );
  }
  return result;
}

Expression _unwrap(Expression expression) {
  var e = expression;
  while (true) {
    if (e is ParenthesizedExpression) {
      e = e.expression;
    } else if (e is PostfixExpression && e.operator.lexeme == '!') {
      e = e.operand;
    } else {
      return e;
    }
  }
}

String _lastName(Expression e) => switch (e) {
  SimpleIdentifier() => e.name,
  PrefixedIdentifier() => e.identifier.name,
  _ => '',
};

String _normalizeAccessor(String source) =>
    source.replaceAll(RegExp(r'[\s!?]'), '');

/// Whether [expression] evaluates to a generated localizations object.
bool _isLocalizationObject(
  Expression expression,
  Set<String> classes,
  Set<String> accessors,
  Set<String> tracked,
) {
  final e = _unwrap(expression);
  if (e is MethodInvocation) {
    final target = e.target;
    final name = e.methodName.name;
    if (name == 'of' && target != null && classes.contains(_lastName(target))) {
      return true;
    }
    if (target == null &&
        name.startsWith('lookup') &&
        classes.contains(name.substring('lookup'.length))) {
      return true;
    }
  }
  if (e is SimpleIdentifier && tracked.contains(e.name)) return true;
  if (accessors.isNotEmpty &&
      accessors.contains(_normalizeAccessor(e.toSource()))) {
    return true;
  }
  return false;
}

/// Collects names of variables, fields and parameters that hold the
/// localizations object, e.g. `final l10n = AppLocalizations.of(context)!;`.
class _TrackingVisitor extends RecursiveAstVisitor<void> {
  _TrackingVisitor(this.classes, this.accessors, this.tracked);

  final Set<String> classes;
  final Set<String> accessors;
  final Set<String> tracked;

  bool _isLocalizationType(String? typeSource) {
    if (typeSource == null) return false;
    final name = typeSource.replaceAll('?', '').split('.').last.trim();
    return classes.contains(name);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final parent = node.parent;
    final typeSource = parent is VariableDeclarationList
        ? parent.type?.toSource()
        : null;
    final initializer = node.initializer;
    if (_isLocalizationType(typeSource) ||
        (initializer != null &&
            _isLocalizationObject(initializer, classes, accessors, const {}))) {
      tracked.add(node.name.lexeme);
    }
    super.visitVariableDeclaration(node);
  }

  static final _parameterPattern = RegExp(
    r'^(?:@\S+\s+)*(?:(?:required|final|covariant|const)\s+)*'
    r'(?:[A-Za-z_$][\w$]*\.)?([A-Za-z_$][\w$]*)\??\s+'
    r'(?:this\.)?([A-Za-z_$][\w$]*)',
  );

  @override
  void visitFormalParameterList(FormalParameterList node) {
    for (final parameter in node.parameters) {
      final match = _parameterPattern.firstMatch(parameter.toSource());
      final name = parameter.name?.lexeme;
      if (match != null && name != null && classes.contains(match[1])) {
        tracked.add(name);
      }
    }
    super.visitFormalParameterList(node);
  }
}

class _UsageVisitor extends RecursiveAstVisitor<void> {
  _UsageVisitor({
    required this.path,
    required this.lineInfo,
    required this.classes,
    required this.accessors,
    required this.lookups,
    required this.keyConstants,
    required this.tracked,
    required this.result,
  });

  final String path;
  final LineInfo lineInfo;
  final Set<String> classes;
  final Set<String> accessors;
  final Set<String> lookups;
  final Map<String, Map<String, String>> keyConstants;
  final Set<String> tracked;
  final UsageScanResult result;

  /// Resolves `LocaleKeys.name` (optionally import-prefixed) to its key.
  String? _keyConstant(Expression expression) {
    final e = _unwrap(expression);
    if (e is PrefixedIdentifier) {
      return keyConstants[e.prefix.name]?[e.identifier.name];
    }
    if (e is PropertyAccess) {
      final target = e.target;
      if (target is PrefixedIdentifier) {
        return keyConstants[target.identifier.name]?[e.propertyName.name];
      }
    }
    return null;
  }

  void _recordKey(String key, AstNode node) {
    result.literalLookups.putIfAbsent(key, () => []).add(_location(node));
  }

  SourceLocation _location(AstNode node) {
    final l = lineInfo.getLocation(node.offset);
    return SourceLocation(path, line: l.lineNumber, column: l.columnNumber);
  }

  bool _isL10n(Expression e) =>
      _isLocalizationObject(e, classes, accessors, tracked);

  void _member(String name, AstNode node) {
    result.generatedMembers.putIfAbsent(name, () => []).add(_location(node));
  }

  void _lookup(Expression keyExpression, AstNode node) {
    final e = _unwrap(keyExpression);
    // Key constants are recorded where they are referenced.
    if (_keyConstant(e) != null) return;
    if (e is StringLiteral) {
      final value = e.stringValue;
      if (value != null) {
        result.literalLookups.putIfAbsent(value, () => []).add(_location(node));
        return;
      }
      if (e is StringInterpolation) {
        final first = e.elements.first;
        final prefix = first is InterpolationString ? first.value : '';
        result.dynamicLookups.add(DynamicLookup(_location(node), prefix));
        return;
      }
    }
    result.dynamicLookups.add(DynamicLookup(_location(node), ''));
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    final name = node.methodName.name;
    if (target != null && _isL10n(target)) {
      _member(name, node.methodName);
    } else if (lookups.contains(name)) {
      final positional = node.argumentList.arguments
          .whereType<Expression>()
          .toList();
      final realTarget = target == null ? null : _unwrap(target);
      if (realTarget is StringLiteral) {
        _lookup(realTarget, node);
      } else if (positional.isNotEmpty) {
        _lookup(positional.first, node);
      } else if (target != null) {
        _lookup(target, node);
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target;
    final name = node.propertyName.name;
    final constant = _keyConstant(node);
    if (constant != null) {
      _recordKey(constant, node);
    } else if (target != null && _isL10n(target)) {
      _member(name, node.propertyName);
    } else if (lookups.contains(name) && target != null) {
      // GetX style: 'key'.tr
      _lookup(target, node);
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final name = node.identifier.name;
    final constant = _keyConstant(node);
    if (constant != null) {
      // Any reference counts: the constant may be passed around before
      // being translated.
      _recordKey(constant, node);
    } else if (_isL10n(node.prefix)) {
      _member(name, node.identifier);
    } else if (lookups.contains(name) &&
        !classes.contains(node.prefix.name) &&
        node.parent is! MethodInvocation) {
      // `key.tr` where `key` is a variable.
      result.dynamicLookups.add(DynamicLookup(_location(node), ''));
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    result.identifiers.add(node.name);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    result.stringLiterals.add(node.value);
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    if (node.name.lexeme == 'supportedLocales') {
      final list = _unwrap(node.argumentExpression);
      if (list is ListLiteral) {
        final locales = <String>[];
        var allLiteral = list.elements.isNotEmpty;
        for (final element in list.elements) {
          final locale = element is Expression ? _literalLocale(element) : null;
          if (locale == null) {
            allLiteral = false;
            break;
          }
          locales.add(locale);
        }
        if (allLiteral) {
          result.supportedLocales.add(
            SupportedLocalesDeclaration(_location(node), locales),
          );
        }
      }
    }
    super.visitNamedArgument(node);
  }

  /// Reads `Locale('en', 'US')` or `Locale.fromSubtags(languageCode: ...)`.
  String? _literalLocale(Expression e) {
    ArgumentList? args;
    String constructor;
    if (e is InstanceCreationExpression) {
      args = e.argumentList;
      constructor = e.constructorName.toSource().replaceFirst(
        RegExp(r'^(?:const|new)\s+'),
        '',
      );
    } else if (e is MethodInvocation) {
      args = e.argumentList;
      final target = e.target;
      constructor = target == null
          ? e.methodName.name
          : '${target.toSource()}.${e.methodName.name}';
    } else {
      return null;
    }
    String? literal(Expression? x) {
      if (x == null) return null;
      final v = _unwrap(x);
      return v is StringLiteral ? v.stringValue : null;
    }

    final positional = args.arguments.whereType<Expression>();
    final named = {
      for (final a in args.arguments.whereType<NamedArgument>())
        a.name.lexeme: a.argumentExpression,
    };
    List<String?> parts;
    if (constructor == 'Locale') {
      parts = [for (final a in positional) literal(a)];
    } else if (constructor == 'Locale.fromSubtags') {
      parts = [
        literal(named['languageCode']) ?? 'und',
        if (named.containsKey('scriptCode')) literal(named['scriptCode']),
        if (named.containsKey('countryCode')) literal(named['countryCode']),
      ];
    } else {
      return null;
    }
    if (parts.isEmpty || parts.any((x) => x == null)) return null;
    return normalizeLocale(parts.whereType<String>().join('_'));
  }
}

/// Collects `static const` string fields of the given key classes.
class _KeyClassVisitor extends RecursiveAstVisitor<void> {
  _KeyClassVisitor(this.classes, this.constants);

  final Set<String> classes;
  final Map<String, Map<String, String>> constants;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final name = node.namePart.typeName.lexeme;
    if (classes.contains(name)) {
      final fields = constants.putIfAbsent(name, () => {});
      for (final member in node.body.childEntities) {
        if (member is! FieldDeclaration ||
            !member.isStatic ||
            !member.fields.isConst) {
          continue;
        }
        for (final variable in member.fields.variables) {
          final initializer = variable.initializer;
          if (initializer is StringLiteral) {
            final value = initializer.stringValue;
            if (value != null) fields[variable.name.lexeme] = value;
          }
        }
      }
    }
    super.visitClassDeclaration(node);
  }
}
