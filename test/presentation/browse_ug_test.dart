import 'package:flutter_test/flutter_test.dart';
import 'package:worship_setlist/domain/url_validator.dart';

void main() {
  group(
    'BrowseUG navigation and tab saving rules (spec.md Section 3 & 5.1)',
    () {
      test('allowed hosts permit navigation', () {
        expect(UrlValidator.isAllowedHost('tabs.ultimate-guitar.com'), isTrue);
        expect(UrlValidator.isAllowedHost('www.ultimate-guitar.com'), isTrue);
      });

      test('disallowed hosts are intercepted', () {
        expect(UrlValidator.isAllowedHost('facebook.com'), isFalse);
        expect(UrlValidator.isAllowedHost('google.com'), isFalse);
        expect(UrlValidator.isAllowedHost('ultimate-guitar.com'), isFalse);
        expect(UrlValidator.isAllowedHost('m.ultimate-guitar.com'), isFalse);
      });

      test('only URLs with /tab/ path are recognized as saveable songs', () {
        final tabUrl = UrlValidator.validateAndNormalize(
          'https://tabs.ultimate-guitar.com/tab/hillsong/oceans-12345',
        );
        expect(tabUrl.isValid, isTrue);

        final exploreUrl = UrlValidator.validateAndNormalize(
          'https://www.ultimate-guitar.com/explore',
        );
        expect(exploreUrl.isValid, isFalse);
        expect(exploreUrl.errorMessage, contains('Path must start with /tab/'));

        final searchUrl = UrlValidator.validateAndNormalize(
          'https://www.ultimate-guitar.com/search.php?search_type=title&value=oceans',
        );
        expect(searchUrl.isValid, isFalse);
      });
    },
  );
}
