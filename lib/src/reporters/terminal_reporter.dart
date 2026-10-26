import '../models/audit_result.dart';
import '../models/diagnostic.dart';

/// How much the terminal reporter prints.
enum Verbosity { quiet, normal, verbose }

/// Renders an [AuditResult] for humans. ANSI colors are used only when
/// [color] is true; the caller decides based on the terminal and `NO_COLOR`.
class TerminalReporter {
  const TerminalReporter({
    this.color = false,
    this.verbosity = Verbosity.normal,
  });

  final bool color;
  final Verbosity verbosity;

  String _wrap(String text, String code) =>
      color ? '\x1B[${code}m$text\x1B[0m' : text;
  String _bold(String t) => _wrap(t, '1');
  String _dim(String t) => _wrap(t, '2');
  String _red(String t) => _wrap(t, '31');
  String _green(String t) => _wrap(t, '32');
  String _yellow(String t) => _wrap(t, '33');
  String _cyan(String t) => _wrap(t, '36');

  String _severity(Severity s) => switch (s) {
    Severity.error => _red('error  '),
    Severity.warning => _yellow('warning'),
    Severity.info => _cyan('info   '),
  };

  String render(AuditResult result) {
    final out = StringBuffer();
    if (verbosity != Verbosity.quiet) {
      out
        ..writeln(_bold('Localization Doctor ${result.toolVersion}'))
        ..writeln('Project: ${result.projectPath}')
        ..writeln();
      _bundles(out, result);
      _coverage(out, result);
      _diagnostics(out, result);
      if (verbosity == Verbosity.verbose) _details(out, result);
    }
    _summary(out, result);
    return out.toString();
  }

  void _bundles(StringBuffer out, AuditResult result) {
    if (result.bundles.isEmpty) return;
    out.writeln(_bold('Translation bundles'));
    for (final b in result.bundles) {
      out.writeln(
        '  ${b.id}  base: ${b.baseLocale ?? '(none)'}  '
        'locales: ${b.locales.join(', ')}',
      );
    }
    out.writeln();
  }

  void _coverage(StringBuffer out, AuditResult result) {
    if (result.coverage.isEmpty) return;
    out.writeln(_bold('Locale coverage'));
    final rows = <List<String>>[
      [
        'Bundle',
        'Locale',
        'Total',
        'Translated',
        'Missing',
        'Empty',
        'Invalid',
        'Coverage',
      ],
      for (final c in result.coverage)
        [
          c.bundle,
          c.locale +
              (c.isBase
                  ? ' (base)'
                  : c.isOptional
                  ? ' (optional)'
                  : '') +
              (c.fileValid ? '' : ' (invalid file)'),
          '${c.total}',
          '${c.translated}',
          '${c.missing}',
          '${c.empty}',
          '${c.invalid}',
          '${_formatPercent(c.percent)}%',
        ],
    ];
    final widths = List<int>.filled(rows.first.length, 0);
    for (final row in rows) {
      for (var i = 0; i < row.length; i++) {
        if (row[i].length > widths[i]) widths[i] = row[i].length;
      }
    }
    for (var r = 0; r < rows.length; r++) {
      final cells = <String>[];
      for (var i = 0; i < rows[r].length; i++) {
        final cell = rows[r][i];
        cells.add(i < 2 ? cell.padRight(widths[i]) : cell.padLeft(widths[i]));
      }
      final line = '  ${cells.join('  ')}'.trimRight();
      out.writeln(r == 0 ? _dim(line) : line);
    }
    out.writeln();
  }

  void _diagnostics(StringBuffer out, AuditResult result) {
    if (result.diagnostics.isEmpty) {
      out
        ..writeln(_green('No localization problems found.'))
        ..writeln();
      return;
    }
    out.writeln(_bold('Diagnostics'));
    for (final d in result.diagnostics) {
      final where = d.location?.toString() ?? d.bundle ?? '';
      out.writeln(
        '  ${_severity(d.severity)} ${_bold(d.code.id)}  '
                '${where.isEmpty ? '' : '$where  '}'
                '${d.confidence == Confidence.definite ? '' : _dim('[${d.confidence.name}]')}'
            .trimRight(),
      );
      out.writeln('    ${d.message}');
      if (verbosity == Verbosity.verbose) {
        for (final related in d.relatedLocations) {
          out.writeln(_dim('    see also: $related'));
        }
      }
      if (d.suggestion != null) {
        out.writeln('    ${_dim('fix:')} ${d.suggestion}');
      }
    }
    out.writeln();
  }

  void _details(StringBuffer out, AuditResult result) {
    out
      ..writeln(_bold('Details'))
      ..writeln('  Dart files scanned: ${result.scannedSourceFiles}');
    if (result.skippedFiles.isNotEmpty) {
      out.writeln('  Skipped files:');
      for (final f in result.skippedFiles) {
        out.writeln('    $f');
      }
    }
    out.writeln();
  }

  void _summary(StringBuffer out, AuditResult result) {
    final errors = result.count(Severity.error);
    final warnings = result.count(Severity.warning);
    final infos = result.count(Severity.info);
    final parts = [
      '$errors error${errors == 1 ? '' : 's'}',
      '$warnings warning${warnings == 1 ? '' : 's'}',
      '$infos info',
      if (result.suppressedCount > 0) '${result.suppressedCount} suppressed',
    ];
    out.writeln('Summary: ${parts.join(', ')}');
    final violations = result.violations.length;
    if (result.passed) {
      out.writeln(_green(_bold('PASSED')));
    } else {
      out.writeln(
        _red(
          _bold(
            'FAILED: $violations violation${violations == 1 ? '' : 's'} '
            'at or above "${result.failOn.name}" severity',
          ),
        ),
      );
    }
  }
}

String _formatPercent(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';
