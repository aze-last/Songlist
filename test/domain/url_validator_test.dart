import 'package:flutter_test/flutter_test.dart';
import 'package:worship_setlist/domain/url_validator.dart';

void main() {
  group('UrlValidator', () {
    test('accepts valid HTTPS UG tab URLs from tabs.ultimate-guitar.com', () {
      const url =
          'https://tabs.ultimate-guitar.com/tab/hillsong-worship/what-a-beautiful-name-chords-1907703';
      final result = UrlValidator.validateAndNormalize(url);
      expect(result.isValid, isTrue);
      expect(result.errorMessage, isNull);
      expect(result.normalizedUrl, url);
    });

    test('accepts valid HTTPS UG tab URLs from www.ultimate-guitar.com', () {
      const url =
          'https://www.ultimate-guitar.com/tab/chris-tomlin/good-good-father-chords-1768407';
      final result = UrlValidator.validateAndNormalize(url);
      expect(result.isValid, isTrue);
      expect(result.errorMessage, isNull);
      expect(result.normalizedUrl, url);
    });

    test('rejects non-HTTPS URLs', () {
      const url =
          'http://tabs.ultimate-guitar.com/tab/hillsong-worship/what-a-beautiful-name-chords-1907703';
      final result = UrlValidator.validateAndNormalize(url);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('HTTPS is required'));
    });

    test('rejects URLs from unallowed hosts', () {
      const url = 'https://google.com/tab/some-song';
      final result = UrlValidator.validateAndNormalize(url);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Host must be ultimate-guitar.com'));
    });

    test('rejects URLs where path does not start with /tab/', () {
      const url = 'https://tabs.ultimate-guitar.com/explore';
      final result = UrlValidator.validateAndNormalize(url);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Path must start with /tab/'));
    });

    test('strips query parameters and fragments during normalization', () {
      const url =
          'https://tabs.ultimate-guitar.com/tab/artist/song-12345?utm_source=share&utm_medium=app#comment-section';
      final result = UrlValidator.validateAndNormalize(url);
      expect(result.isValid, isTrue);
      expect(
        result.normalizedUrl,
        'https://tabs.ultimate-guitar.com/tab/artist/song-12345',
      );
    });

    test(
      'handles trailing slashes cleanly and normalizes casing of scheme/host',
      () {
        const url =
            'HTTPS://TABS.ULTIMATE-GUITAR.COM/tab/artist/song-12345/?foo=bar';
        final result = UrlValidator.validateAndNormalize(url);
        expect(result.isValid, isTrue);
        expect(
          result.normalizedUrl,
          'https://tabs.ultimate-guitar.com/tab/artist/song-12345',
        );
      },
    );

    test('rejects malformed or empty URLs', () {
      expect(UrlValidator.validateAndNormalize('').isValid, isFalse);
      expect(UrlValidator.validateAndNormalize('   ').isValid, isFalse);
      expect(UrlValidator.validateAndNormalize('not-a-url').isValid, isFalse);
    });

    test('isDuplicate detects identical URLs after normalization', () {
      const url1 =
          'https://tabs.ultimate-guitar.com/tab/artist/song-123?utm_campaign=xyz';
      const url2 =
          'https://tabs.ultimate-guitar.com/tab/artist/song-123#verse1';
      expect(UrlValidator.areDuplicate(url1, url2), isTrue);
    });

    test('isAllowedHost verifies allowed hosts for WebView navigation', () {
      expect(UrlValidator.isAllowedHost('tabs.ultimate-guitar.com'), isTrue);
      expect(UrlValidator.isAllowedHost('www.ultimate-guitar.com'), isTrue);
      expect(UrlValidator.isAllowedHost('ultimate-guitar.com'), isFalse);
      expect(UrlValidator.isAllowedHost('evil.com'), isFalse);
      expect(UrlValidator.isAllowedHost(null), isFalse);
    });
  });
}
