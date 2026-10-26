import 'package:localization_doctor/src/discovery/locale_name.dart';
import 'package:test/test.dart';

void main() {
  group('detectLocaleFromFileName', () {
    final cases = <String, (String, String)?>{
      'app_en': ('app_', 'en'),
      'app_ur': ('app_', 'ur'),
      'app_en_US': ('app_', 'en_US'),
      'app_pt_BR': ('app_', 'pt_BR'),
      'intl_zh_Hant_TW': ('intl_', 'zh_Hant_TW'),
      'intl_zh_Hant': ('intl_', 'zh_Hant'),
      'messages_es_419': ('messages_', 'es_419'),
      'my_app_fr': ('my_app_', 'fr'),
      'en': ('', 'en'),
      'fil': ('', 'fil'),
      'en-US': ('', 'en_US'),
      'en_us': ('', 'en_US'),
      'en-us': ('', 'en_US'),
      'zh_Hant_TW': ('', 'zh_Hant_TW'),
      'translations': null,
      'app': ('', 'app'),
      'l10n': null,
      'untranslated_messages': null,
      'app_EN': null,
    };
    cases.forEach((stem, expected) {
      test(stem, () {
        final detected = detectLocaleFromFileName(stem);
        if (expected == null) {
          expect(detected, isNull);
        } else {
          expect(detected, isNotNull);
          expect((detected!.prefix, detected.locale), expected);
        }
      });
    });
  });

  group('normalizeLocale', () {
    test('normalizes separators and casing', () {
      expect(normalizeLocale('EN-us'), 'en_US');
      expect(normalizeLocale('zh-hant-tw'), 'zh_Hant_TW');
      expect(normalizeLocale('es_419'), 'es_419');
    });

    test('rejects invalid identifiers', () {
      expect(normalizeLocale('english'), isNull);
      expect(normalizeLocale('e'), isNull);
      expect(normalizeLocale('en_US_x_y'), isNull);
      expect(normalizeLocale(''), isNull);
    });

    test('languageOf', () {
      expect(languageOf('pt_BR'), 'pt');
      expect(languageOf('ur'), 'ur');
    });
  });
}
