import 'package:localization_doctor/src/source/usage_scanner.dart';
import 'package:test/test.dart';

import '../support/test_project.dart';

UsageScanResult scan(
  Map<String, String> files, {
  List<String> exclude = const [],
  List<String> classes = const ['AppLocalizations'],
  List<String> accessors = const [],
  List<String> lookups = const ['tr', 'plural', 'translate'],
  List<String> dirs = const ['lib'],
}) {
  final project = TestProject.create(files);
  return scanSourceUsage(
    project.root,
    UsageScanOptions(
      sourceDirectories: dirs,
      exclude: exclude,
      localizationClasses: classes,
      accessors: accessors,
      jsonLookupFunctions: lookups,
    ),
  );
}

void main() {
  group('generated localization access', () {
    test('recognizes !, ? and plain access on .of(context)', () {
      final result = scan({
        'lib/a.dart': '''
void f(context) {
  AppLocalizations.of(context)!.bang;
  AppLocalizations.of(context)?.nullAware;
  AppLocalizations.of(context).plain;
  (AppLocalizations.of(context)!).paren;
  AppLocalizations.of(context)!.method('x', 2);
  gen.AppLocalizations.of(context)!.prefixed;
}
''',
      });
      expect(
        result.generatedMembers.keys,
        containsAll([
          'bang',
          'nullAware',
          'plain',
          'paren',
          'method',
          'prefixed',
        ]),
      );
      expect(result.generatedMembers['bang']!.single.line, 2);
    });

    test('tracks variables, fields and parameters', () {
      final result = scan({
        'lib/a.dart': '''
class W {
  W(this.loc);
  final AppLocalizations loc;
  AppLocalizations? maybe;
  void build(context, AppLocalizations param, {required AppLocalizations named}) {
    final l10n = AppLocalizations.of(context)!;
    final AppLocalizations typed = get();
    l10n.fromVariable;
    typed.fromTyped;
    loc.fromField;
    maybe?.fromNullableField;
    param.fromParameter;
    named.fromNamedParameter;
  }
}
''',
      });
      expect(
        result.generatedMembers.keys,
        containsAll([
          'fromVariable',
          'fromTyped',
          'fromField',
          'fromNullableField',
          'fromParameter',
          'fromNamedParameter',
        ]),
      );
    });

    test('supports a configurable class name and accessor', () {
      final result = scan(
        {
          'lib/a.dart': '''
void f(context) {
  S.of(context).fromS;
  context.l10n.fromAccessor;
  context.l10n!.fromBangAccessor;
  AppLocalizations.of(context)!.notTracked;
}
''',
        },
        classes: ['S'],
        accessors: ['context.l10n'],
      );
      expect(
        result.generatedMembers.keys,
        containsAll(['fromS', 'fromAccessor', 'fromBangAccessor']),
      );
      expect(result.generatedMembers.containsKey('notTracked'), isFalse);
    });

    test('lookupAppLocalizations(locale) is recognized', () {
      final result = scan({
        'lib/a.dart': 'void f(l) => lookupAppLocalizations(l).viaLookup;',
      });
      expect(result.generatedMembers.keys, contains('viaLookup'));
    });

    test('unrelated member access is not counted', () {
      final result = scan({
        'lib/a.dart': 'void f(theme) { theme.homeTitle; Other.of(x).title; }',
      });
      expect(result.generatedMembers, isEmpty);
      expect(result.identifiers, contains('homeTitle'));
    });
  });

  group('JSON lookups', () {
    test('string literal lookups (easy_localization and GetX styles)', () {
      final result = scan({
        'lib/a.dart': '''
void f(context) {
  'a.literalTr'.tr();
  tr('b.function');
  context.tr('c.contextTr');
  plural('d.plural', 3);
  'e.getx'.tr;
  'f' 'g.adjacent'.tr();
  'h.args'.tr(args: ['x']);
}
''',
      });
      expect(result.literalLookups.keys, {
        'a.literalTr',
        'b.function',
        'c.contextTr',
        'd.plural',
        'e.getx',
        'fg.adjacent',
        'h.args',
      });
      expect(result.dynamicLookups, isEmpty);
    });

    test('interpolated and variable keys are dynamic lookups', () {
      final result = scan({
        'lib/a.dart': r'''
void f(String code, String key) {
  'errors.$code'.tr();
  tr('status.${code}.label');
  key.tr();
  tr(key);
  key.tr;
}
''',
      });
      expect(result.dynamicLookups.map((d) => d.prefix).toList(), [
        'errors.',
        'status.',
        '',
        '',
        '',
      ]);
    });

    test('collects other string literals', () {
      final result = scan({'lib/a.dart': "const keys = ['menu.open'];"});
      expect(result.stringLiterals, contains('menu.open'));
      expect(result.literalLookups, isEmpty);
    });
  });

  group('file selection', () {
    test('skips generated, excluded and hidden files', () {
      final result = scan(
        {
          'lib/a.dart': 'void a() {}',
          'lib/a.g.dart': 'void g() {}',
          'lib/a.freezed.dart': 'void f() {}',
          'lib/generated/x.dart': 'void x() {}',
          'lib/legacy/old.dart': 'void o() {}',
          'lib/.hidden/h.dart': 'void h() {}',
          'lib/build/b.dart': 'void b() {}',
          'lib/l10n/app_localizations.dart':
              'abstract class AppLocalizations { String get title; }',
          'lib/l10n/app_localizations_en.dart':
              'class AppLocalizationsEn extends AppLocalizations {}',
          'test/t.dart': 'void t() {}',
        },
        exclude: ['lib/legacy/**'],
      );
      expect(result.scannedFiles, ['lib/a.dart']);
      expect(result.skippedGeneratedFiles, [
        'lib/l10n/app_localizations.dart',
        'lib/l10n/app_localizations_en.dart',
      ]);
    });

    test('files with syntax errors are still scanned', () {
      final result = scan({
        'lib/a.dart': 'void f(context) { AppLocalizations.of(context)!.ok; ',
      });
      expect(result.generatedMembers.keys, contains('ok'));
    });

    test('missing source directory is a configuration warning', () {
      final result = scan({}, dirs: ['src']);
      expect(
        result.diagnostics.single.message,
        contains('"src" does not exist'),
      );
    });
  });

  test('reads literal supportedLocales lists', () {
    final result = scan({
      'lib/a.dart': '''
f() => MaterialApp(
  supportedLocales: const [
    Locale('en'),
    Locale('pt', 'BR'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ],
);
g() => MaterialApp(supportedLocales: AppLocalizations.supportedLocales);
''',
    });
    expect(result.supportedLocales.single.locales, ['en', 'pt_BR', 'zh_Hant']);
  });
}
