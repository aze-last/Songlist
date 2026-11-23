import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_setlist/domain/update_checker.dart';

void main() {
  group(
    'UpdateChecker Semver & Version Comparison (spec.md Section 8 & 10)',
    () {
      test('recognizes newer version with leading v', () {
        expect(
          UpdateChecker.isNewerVersion(
            currentVersion: '1.0.0',
            latestTag: 'v1.0.1',
          ),
          isTrue,
        );
      });

      test('recognizes newer version without leading v', () {
        expect(
          UpdateChecker.isNewerVersion(
            currentVersion: '1.0.0',
            latestTag: '1.1.0',
          ),
          isTrue,
        );
      });

      test('real semver comparison: 1.0.10 is greater than 1.0.9', () {
        expect(
          UpdateChecker.isNewerVersion(
            currentVersion: '1.0.9',
            latestTag: 'v1.0.10',
          ),
          isTrue,
        );
        expect(
          UpdateChecker.isNewerVersion(
            currentVersion: '1.0.10',
            latestTag: 'v1.0.9',
          ),
          isFalse,
        );
      });

      test('never downgrades: rejects older or identical version', () {
        expect(
          UpdateChecker.isNewerVersion(
            currentVersion: '2.0.0',
            latestTag: 'v1.9.9',
          ),
          isFalse,
        );
        expect(
          UpdateChecker.isNewerVersion(
            currentVersion: '1.0.0',
            latestTag: 'v1.0.0',
          ),
          isFalse,
        );
      });

      test('ignores malformed version tags without crashing', () {
        expect(
          UpdateChecker.isNewerVersion(
            currentVersion: '1.0.0',
            latestTag: 'beta-build',
          ),
          isFalse,
        );
        expect(
          UpdateChecker.isNewerVersion(currentVersion: '1.0.0', latestTag: ''),
          isFalse,
        );
      });

      test('ignores current build suffix during semver comparison', () {
        expect(
          UpdateChecker.isNewerVersion(
            currentVersion: '1.0.0+1',
            latestTag: 'v1.0.1',
          ),
          isTrue,
        );
        expect(
          UpdateChecker.isNewerVersion(
            currentVersion: '1.0.1+5',
            latestTag: 'v1.0.1',
          ),
          isFalse,
        );
      });

      test('respects skipped version configuration', () {
        expect(
          UpdateChecker.isNewerVersion(
            currentVersion: '1.0.0',
            latestTag: 'v1.2.0',
            skippedVersion: 'v1.2.0',
          ),
          isFalse,
        );
        expect(
          UpdateChecker.isNewerVersion(
            currentVersion: '1.0.0',
            latestTag: 'v1.2.0',
            skippedVersion: 'v1.1.0',
          ),
          isTrue,
        );
      });
    },
  );

  group('UpdateChecker GitHub Release Parsing (spec.md Section 8 & 10)', () {
    test('extracts apk and sha256 assets from valid release JSON', () {
      final releaseJson = {
        'tag_name': 'v1.0.1',
        'draft': false,
        'prerelease': false,
        'body': 'Bug fixes and performance improvements.',
        'assets': [
          {
            'name': 'worship-setlist-v1.0.1.apk',
            'browser_download_url': 'https://github.com/aze-last/worship_setlist/releases/download/v1.0.1/worship-setlist-v1.0.1.apk',
            'size': 15000000,
          },
          {
            'name': 'worship-setlist-v1.0.1.apk.sha256',
            'browser_download_url': 'https://github.com/aze-last/worship_setlist/releases/download/v1.0.1/worship-setlist-v1.0.1.apk.sha256',
            'size': 64,
          },
        ],
      };

      final parsed = UpdateChecker.parseRelease(releaseJson);
      expect(parsed, isNotNull);
      expect(parsed!.tagName, equals('v1.0.1'));
      expect(
        parsed.releaseNotes,
        equals('Bug fixes and performance improvements.'),
      );
      expect(parsed.apkAssetName, equals('worship-setlist-v1.0.1.apk'));
      expect(
        parsed.apkDownloadUrl,
        equals(
          'https://github.com/aze-last/worship_setlist/releases/download/v1.0.1/worship-setlist-v1.0.1.apk',
        ),
      );
      expect(
        parsed.sha256AssetName,
        equals('worship-setlist-v1.0.1.apk.sha256'),
      );
    });

    test('ignores draft releases', () {
      final releaseJson = {
        'tag_name': 'v1.0.1',
        'draft': true,
        'prerelease': false,
        'assets': [
          {
            'name': 'app.apk',
            'browser_download_url': 'https://github.com/app.apk',
          },
          {
            'name': 'app.apk.sha256',
            'browser_download_url': 'https://github.com/app.apk.sha256',
          },
        ],
      };

      expect(UpdateChecker.parseRelease(releaseJson), isNull);
    });

    test('ignores prereleases', () {
      final releaseJson = {
        'tag_name': 'v1.0.1-rc1',
        'draft': false,
        'prerelease': true,
        'assets': [
          {
            'name': 'app.apk',
            'browser_download_url': 'https://github.com/app.apk',
          },
          {
            'name': 'app.apk.sha256',
            'browser_download_url': 'https://github.com/app.apk.sha256',
          },
        ],
      };

      expect(UpdateChecker.parseRelease(releaseJson), isNull);
    });

    test('rejects release missing .apk asset', () {
      final releaseJson = {
        'tag_name': 'v1.0.1',
        'draft': false,
        'prerelease': false,
        'assets': [
          {
            'name': 'app.apk.sha256',
            'browser_download_url': 'https://github.com/app.apk.sha256',
          },
        ],
      };

      expect(UpdateChecker.parseRelease(releaseJson), isNull);
    });

    test('rejects release missing .sha256 asset', () {
      final releaseJson = {
        'tag_name': 'v1.0.1',
        'draft': false,
        'prerelease': false,
        'assets': [
          {
            'name': 'app.apk',
            'browser_download_url': 'https://github.com/app.apk',
          },
        ],
      };

      expect(UpdateChecker.parseRelease(releaseJson), isNull);
    });
  });

  group('UpdateChecker Allowed Hosts (spec.md Section 8)', () {
    test('permits authorized GitHub release hosts over HTTPS', () {
      expect(
        UpdateChecker.isAllowedDownloadUrl(
          'https://github.com/aze-last/repo/releases/download/v1.0/app.apk',
        ),
        isTrue,
      );
      expect(
        UpdateChecker.isAllowedDownloadUrl(
          'https://objects.githubusercontent.com/github-production-release-asset-2e65be/12345/app.apk',
        ),
        isTrue,
      );
      expect(
        UpdateChecker.isAllowedDownloadUrl(
          'https://github-releases.githubusercontent.com/12345/app.apk',
        ),
        isTrue,
      );
      expect(
        UpdateChecker.isAllowedDownloadUrl(
          'https://api.github.com/repos/aze-last/repo/releases',
        ),
        isTrue,
      );
    });

    test('rejects unauthorized or non-HTTPS hosts', () {
      expect(
        UpdateChecker.isAllowedDownloadUrl(
          'http://github.com/aze-last/repo/releases/download/v1.0/app.apk',
        ),
        isFalse,
      );
      expect(
        UpdateChecker.isAllowedDownloadUrl('https://evil.com/app.apk'),
        isFalse,
      );
      expect(
        UpdateChecker.isAllowedDownloadUrl(
          'https://gitlab.com/aze-last/repo/releases/app.apk',
        ),
        isFalse,
      );
    });
  });

  group(
    'UpdateChecker SHA-256 Checksum Verification (spec.md Section 8 & 10)',
    () {
      test('verifies matching SHA-256 with plain hash', () {
        final sampleBytes = utf8.encode('Sample APK File Content');
        final expectedHash = sha256.convert(sampleBytes).toString();

        expect(
          UpdateChecker.verifyChecksum(
            fileBytes: sampleBytes,
            checksumFileContent: expectedHash,
          ),
          isTrue,
        );
      });

      test(
        'verifies matching SHA-256 with standard hash + filename format',
        () {
          final sampleBytes = utf8.encode('Sample APK File Content');
          final expectedHash = sha256.convert(sampleBytes).toString();
          final fileFormat = '$expectedHash  worship-setlist-v1.0.1.apk\n';

          expect(
            UpdateChecker.verifyChecksum(
              fileBytes: sampleBytes,
              checksumFileContent: fileFormat,
            ),
            isTrue,
          );
        },
      );

      test('detects SHA-256 mismatch (tampered content)', () {
        final sampleBytes = utf8.encode('Original Content');
        final tamperedBytes = utf8.encode('Tampered Content');
        final expectedHash = sha256.convert(sampleBytes).toString();

        expect(
          UpdateChecker.verifyChecksum(
            fileBytes: tamperedBytes,
            checksumFileContent: expectedHash,
          ),
          isFalse,
        );
      });
    },
  );

  group('UpdateChecker 24h Throttle Calculation (spec.md Section 8)', () {
    final now = DateTime(2026, 11, 23, 12, 0);

    test('triggers check if never checked before', () {
      expect(
        UpdateChecker.shouldAutoCheck(lastCheckAt: null, now: now),
        isTrue,
      );
    });

    test('triggers check if 24 hours or more have elapsed', () {
      expect(
        UpdateChecker.shouldAutoCheck(
          lastCheckAt: now.subtract(const Duration(hours: 24)),
          now: now,
        ),
        isTrue,
      );
      expect(
        UpdateChecker.shouldAutoCheck(
          lastCheckAt: now.subtract(const Duration(hours: 30)),
          now: now,
        ),
        isTrue,
      );
    });

    test('throttles check if checked less than 24 hours ago', () {
      expect(
        UpdateChecker.shouldAutoCheck(
          lastCheckAt: now.subtract(const Duration(hours: 23)),
          now: now,
        ),
        isFalse,
      );
      expect(
        UpdateChecker.shouldAutoCheck(
          lastCheckAt: now.subtract(const Duration(minutes: 5)),
          now: now,
        ),
        isFalse,
      );
    });
  });
}
