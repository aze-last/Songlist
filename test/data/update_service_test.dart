import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:worship_setlist/data/services/update_service.dart';

void main() {
  late Directory testTempDir;

  setUp(() {
    testTempDir = Directory.systemTemp.createTempSync('update_test_');
  });

  tearDown(() {
    if (testTempDir.existsSync()) {
      testTempDir.deleteSync(recursive: true);
    }
  });

  Map<String, dynamic> createReleaseJson({
    required String tagName,
    String body = 'Release notes',
    String apkUrl = 'https://github.com/aze-last/worship_setlist/releases/download/v1.0.1/app.apk',
    String shaUrl = 'https://github.com/aze-last/worship_setlist/releases/download/v1.0.1/app.apk.sha256',
  }) {
    return {
      'tag_name': tagName,
      'draft': false,
      'prerelease': false,
      'body': body,
      'assets': [
        {'name': 'app.apk', 'browser_download_url': apkUrl, 'size': 1024},
        {'name': 'app.apk.sha256', 'browser_download_url': shaUrl, 'size': 64},
      ],
    };
  }

  group('UpdateService.checkForUpdate (spec.md Section 8)', () {
    test('detects available update when remote version is newer', () async {
      final releaseJson = createReleaseJson(tagName: 'v1.1.0');
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode(releaseJson),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = UpdateService(
        httpClient: mockClient,
        githubOwner: 'aze-last',
        githubRepo: 'worship_setlist',
        currentVersion: '1.0.0',
        tempDirProvider: () async => testTempDir,
      );

      final result = await service.checkForUpdate(manual: true);

      expect(result.status, equals(UpdateCheckStatus.updateAvailable));
      expect(result.releaseInfo, isNotNull);
      expect(result.releaseInfo!.tagName, equals('v1.1.0'));
      expect(result.releaseInfo!.releaseNotes, equals('Release notes'));
    });

    test(
      'returns upToDate when versions are identical or remote is older',
      () async {
        final releaseJson = createReleaseJson(tagName: 'v1.0.0');
        final mockClient = MockClient((request) async {
          return http.Response(jsonEncode(releaseJson), 200);
        });

        final service = UpdateService(
          httpClient: mockClient,
          githubOwner: 'aze-last',
          githubRepo: 'worship_setlist',
          currentVersion: '1.0.0',
          tempDirProvider: () async => testTempDir,
        );

        final result = await service.checkForUpdate(manual: true);
        expect(result.status, equals(UpdateCheckStatus.upToDate));
      },
    );

    test('respects skipped version during check', () async {
      final releaseJson = createReleaseJson(tagName: 'v1.2.0');
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(releaseJson), 200);
      });

      final service = UpdateService(
        httpClient: mockClient,
        githubOwner: 'aze-last',
        githubRepo: 'worship_setlist',
        currentVersion: '1.0.0',
        skippedVersion: 'v1.2.0',
        tempDirProvider: () async => testTempDir,
      );

      final result = await service.checkForUpdate(manual: true);
      expect(result.status, equals(UpdateCheckStatus.upToDate));
    });

    test('auto-check respects 24-hour throttling', () async {
      var requestCount = 0;
      final releaseJson = createReleaseJson(tagName: 'v1.2.0');
      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response(jsonEncode(releaseJson), 200);
      });

      final recentCheck = DateTime.now().subtract(const Duration(hours: 2));
      final service = UpdateService(
        httpClient: mockClient,
        githubOwner: 'aze-last',
        githubRepo: 'worship_setlist',
        currentVersion: '1.0.0',
        lastCheckAt: recentCheck,
        tempDirProvider: () async => testTempDir,
      );

      final result = await service.checkForUpdate(manual: false);
      expect(result.status, equals(UpdateCheckStatus.throttled));
      expect(requestCount, equals(0));
    });

    test('handles unconfigured repository placeholder gracefully', () async {
      final service = UpdateService(
        httpClient: MockClient((request) async => http.Response('', 200)),
        githubOwner: 'aze-last',
        githubRepo: '<REPO_NAME>',
        currentVersion: '1.0.0',
        tempDirProvider: () async => testTempDir,
      );

      final result = await service.checkForUpdate(manual: true);
      expect(result.status, equals(UpdateCheckStatus.error));
      expect(result.errorMessage, contains('Repository not configured'));
    });

    test('handles 404 or repository not configured error gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final service = UpdateService(
        httpClient: mockClient,
        githubOwner: 'aze-last',
        githubRepo: 'worship_setlist',
        currentVersion: '1.0.0',
        tempDirProvider: () async => testTempDir,
      );

      final result = await service.checkForUpdate(manual: true);
      expect(result.status, equals(UpdateCheckStatus.error));
      expect(result.errorMessage, contains('No releases found'));
    });

    test('handles 403 rate limiting gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Rate limit exceeded', 403);
      });

      final service = UpdateService(
        httpClient: mockClient,
        githubOwner: 'aze-last',
        githubRepo: 'worship_setlist',
        currentVersion: '1.0.0',
        tempDirProvider: () async => testTempDir,
      );

      final result = await service.checkForUpdate(manual: true);
      expect(result.status, equals(UpdateCheckStatus.error));
      expect(result.errorMessage, contains('rate limit'));
    });
  });

  group('UpdateService Download and Checksum Verification (spec.md Section 8 & 10)', () {
    test(
      'successfully downloads and verifies APK with matching SHA-256',
      () async {
        final sampleApkBytes = utf8.encode('VALID_APK_PAYLOAD_TEST');
        final actualHash = sha256.convert(sampleApkBytes).toString();
        final shaFileContent = '$actualHash  app.apk\n';

        final mockClient = MockClient((request) async {
          if (request.url.path.endsWith('.sha256')) {
            return http.Response(shaFileContent, 200);
          } else if (request.url.path.endsWith('.apk')) {
            return http.Response.bytes(sampleApkBytes, 200);
          }
          return http.Response('Not found', 404);
        });

        String? installedPath;
        final service = UpdateService(
          httpClient: mockClient,
          githubOwner: 'aze-last',
          githubRepo: 'worship_setlist',
          currentVersion: '1.0.0',
          tempDirProvider: () async => testTempDir,
          onInstallApk: (path) async {
            installedPath = path;
            return true;
          },
        );

        final progressEvents = <double>[];
        final releaseInfo = UpdateService.parseReleaseInfo(
          createReleaseJson(
            tagName: 'v1.1.0',
            apkUrl: 'https://github.com/aze-last/worship_setlist/releases/download/v1.1.0/app.apk',
            shaUrl: 'https://github.com/aze-last/worship_setlist/releases/download/v1.1.0/app.apk.sha256',
          ),
        )!;

        final downloadedFile = await service.downloadAndVerifyApk(
          releaseInfo: releaseInfo,
          onProgress: (p) => progressEvents.add(p),
        );

        expect(downloadedFile, isNotNull);
        expect(downloadedFile!.existsSync(), isTrue);
        expect(downloadedFile.readAsBytesSync(), equals(sampleApkBytes));
        expect(progressEvents.isNotEmpty, isTrue);

        // Trigger installer
        final installSuccess = await service.installApk(downloadedFile.path);
        expect(installSuccess, isTrue);
        expect(installedPath, equals(downloadedFile.path));
      },
    );

    test(
      'deletes APK file immediately and aborts if SHA-256 does not match',
      () async {
        final sampleApkBytes = utf8.encode('CORRUPTED_OR_TAMPERED_APK_PAYLOAD');
        final wrongHash =
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
        final shaFileContent = '$wrongHash  app.apk\n';

        final mockClient = MockClient((request) async {
          if (request.url.path.endsWith('.sha256')) {
            return http.Response(shaFileContent, 200);
          } else if (request.url.path.endsWith('.apk')) {
            return http.Response.bytes(sampleApkBytes, 200);
          }
          return http.Response('Not found', 404);
        });

        final service = UpdateService(
          httpClient: mockClient,
          githubOwner: 'aze-last',
          githubRepo: 'worship_setlist',
          currentVersion: '1.0.0',
          tempDirProvider: () async => testTempDir,
        );

        final releaseInfo = UpdateService.parseReleaseInfo(
          createReleaseJson(
            tagName: 'v1.1.0',
            apkUrl: 'https://github.com/aze-last/worship_setlist/releases/download/v1.1.0/app.apk',
            shaUrl: 'https://github.com/aze-last/worship_setlist/releases/download/v1.1.0/app.apk.sha256',
          ),
        )!;

        expect(
          () async =>
              await service.downloadAndVerifyApk(releaseInfo: releaseInfo),
          throwsA(isA<ChecksumMismatchException>()),
        );

        // Verify no APK files left in tempDir
        final remainingApks = testTempDir.listSync().where(
          (f) => f.path.endsWith('.apk'),
        );
        expect(remainingApks.isEmpty, isTrue);
      },
    );

    test(
      'deleteCachedApks removes all leftover .apk files from temp dir',
      () async {
        final oldApk1 = File('${testTempDir.path}/update_1.apk')
          ..writeAsStringSync('old1');
        final oldApk2 = File('${testTempDir.path}/update_2.apk')
          ..writeAsStringSync('old2');
        final otherFile = File('${testTempDir.path}/keep_me.txt')
          ..writeAsStringSync('text');

        final service = UpdateService(
          httpClient: http.Client(),
          currentVersion: '1.0.0',
          tempDirProvider: () async => testTempDir,
        );

        await service.deleteCachedApks();

        expect(oldApk1.existsSync(), isFalse);
        expect(oldApk2.existsSync(), isFalse);
        expect(otherFile.existsSync(), isTrue);
      },
    );
  });
}
