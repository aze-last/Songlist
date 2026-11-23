import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/data/services/backup_service.dart';
import 'package:worship_setlist/data/services/update_service.dart';
import 'package:worship_setlist/domain/update_checker.dart';
import 'package:worship_setlist/presentation/providers/database_provider.dart';
import 'package:worship_setlist/presentation/screens/settings/settings_screen.dart';
import 'package:worship_setlist/presentation/widgets/update_dialog.dart';
import 'package:worship_setlist/presentation/widgets/update_progress_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory testTempDir;

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'Worship Setlist',
      packageName: 'com.worship.setlist',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    testTempDir = Directory.systemTemp.createTempSync('update_ui_test_');
  });

  tearDown(() async {
    await db.close();
    if (testTempDir.existsSync()) {
      testTempDir.deleteSync(recursive: true);
    }
  });

  Future<void> tearDownWidget(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  const sampleRelease = ReleaseUpdateInfo(
    tagName: 'v1.2.0',
    releaseNotes: '• Major performance overhaul\n• Real semver support',
    apkAssetName: 'worship-setlist-v1.2.0.apk',
    apkDownloadUrl: 'https://github.com/aze-last/worship_setlist/releases/download/v1.2.0/app.apk',
    apkSize: 2048,
    sha256AssetName: 'worship-setlist-v1.2.0.apk.sha256',
    sha256DownloadUrl: 'https://github.com/aze-last/worship_setlist/releases/download/v1.2.0/app.apk.sha256',
  );

  group('UpdateDialog Widget Tests (spec.md Section 8)', () {
    testWidgets('displays versions, release notes, and 3 action buttons', (
      tester,
    ) async {
      UpdateAction? chosenAction;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                chosenAction = await showDialog<UpdateAction>(
                  context: context,
                  builder: (_) => const UpdateDialog(
                    currentVersion: '1.0.0',
                    releaseInfo: sampleRelease,
                  ),
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('update_dialog')), findsOneWidget);
      expect(find.text('1.0.0'), findsOneWidget);
      expect(find.text('v1.2.0'), findsOneWidget);
      expect(find.textContaining('Major performance overhaul'), findsOneWidget);
      expect(find.byKey(const Key('skip_version_button')), findsOneWidget);
      expect(find.byKey(const Key('update_later_button')), findsOneWidget);
      expect(find.byKey(const Key('update_now_button')), findsOneWidget);

      // Tap Later
      await tester.tap(find.byKey(const Key('update_later_button')));
      await tester.pumpAndSettle();

      expect(chosenAction, equals(UpdateAction.later));
      expect(find.byKey(const Key('update_dialog')), findsNothing);
    });

    testWidgets('tapping Skip returns UpdateAction.skip', (tester) async {
      UpdateAction? chosenAction;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                chosenAction = await showDialog<UpdateAction>(
                  context: context,
                  builder: (_) => const UpdateDialog(
                    currentVersion: '1.0.0',
                    releaseInfo: sampleRelease,
                  ),
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('skip_version_button')));
      await tester.pumpAndSettle();

      expect(chosenAction, equals(UpdateAction.skip));
    });

    testWidgets('tapping Update now returns UpdateAction.updateNow', (
      tester,
    ) async {
      UpdateAction? chosenAction;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                chosenAction = await showDialog<UpdateAction>(
                  context: context,
                  builder: (_) => const UpdateDialog(
                    currentVersion: '1.0.0',
                    releaseInfo: sampleRelease,
                  ),
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('update_now_button')));
      await tester.pumpAndSettle();

      expect(chosenAction, equals(UpdateAction.updateNow));
    });
  });

  group('UpdateProgressDialog Widget Tests', () {
    testWidgets('displays progress bar, percentage, and message', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: UpdateProgressDialog(
            progress: 0.65,
            statusMessage: 'Downloading...',
          ),
        ),
      );

      expect(find.byKey(const Key('update_progress_dialog')), findsOneWidget);
      expect(find.text('65%'), findsOneWidget);
      expect(find.text('Downloading...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });

  group('SettingsScreen Update Integration (spec.md Section 8)', () {
    testWidgets('manual check notifies when app is up to date', (tester) async {
      final serviceWithUpToDate = _MockUpdateService(
        status: UpdateCheckStatus.upToDate,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            updateServiceProvider.overrideWithValue(serviceWithUpToDate),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Check button
      await tester.tap(find.byKey(const Key('check_updates_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('App is up to date'), findsOneWidget);

      // Database should have recorded lastUpdateCheck
      final settings = await db.getOrCreateSettings();
      expect(settings.lastUpdateCheck, isNotNull);

      await tearDownWidget(tester);
    });

    testWidgets('manual check opens UpdateDialog and handles skip version', (
      tester,
    ) async {
      final serviceWithUpdate = _MockUpdateService(
        status: UpdateCheckStatus.updateAvailable,
        releaseInfo: sampleRelease,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            updateServiceProvider.overrideWithValue(serviceWithUpdate),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('check_updates_button')));
      await tester.pumpAndSettle();

      // Verify UpdateDialog is shown
      expect(find.byKey(const Key('update_dialog')), findsOneWidget);
      expect(find.text('v1.2.0'), findsOneWidget);

      // Tap Skip this version
      await tester.tap(find.byKey(const Key('skip_version_button')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Version v1.2.0 will be skipped'),
        findsOneWidget,
      );

      // Verify stored in DB
      final settings = await db.getOrCreateSettings();
      expect(settings.skippedVersion, equals('v1.2.0'));

      await tearDownWidget(tester);
    });

    testWidgets(
      'manual check offers backup before update and triggers install',
      (tester) async {
        String? installedApkPath;
        final fakeDownloadedFile = File('${testTempDir.path}/fake.apk')
          ..writeAsStringSync('apk');

        final serviceWithUpdate = _MockUpdateService(
          status: UpdateCheckStatus.updateAvailable,
          releaseInfo: sampleRelease,
          mockApkFile: fakeDownloadedFile,
          onInstallApkCallback: (path) async {
            installedApkPath = path;
            return true;
          },
        );

        final backupService = BackupService(
          db,
          tempDirProvider: () async => testTempDir,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              backupServiceProvider.overrideWithValue(backupService),
              updateServiceProvider.overrideWithValue(serviceWithUpdate),
            ],
            child: const MaterialApp(home: SettingsScreen()),
          ),
        );

        await tester.pumpAndSettle();

        // Tap Check
        await tester.tap(find.byKey(const Key('check_updates_button')));
        await tester.pumpAndSettle();

        // In UpdateDialog, tap "Update now"
        await tester.tap(find.byKey(const Key('update_now_button')));
        await tester.pumpAndSettle();

        // "Backup Before Update?" dialog should appear
        expect(
          find.byKey(const Key('backup_before_update_dialog')),
          findsOneWidget,
        );

        // Tap "Skip Backup" to proceed directly to download
        await tester.tap(
          find.byKey(const Key('skip_backup_before_update_button')),
        );
        await tester.pumpAndSettle();

        // Verify installation was triggered with the APK file path
        expect(installedApkPath, equals(fakeDownloadedFile.path));

        await tearDownWidget(tester);
      },
    );
  });
}

class _MockUpdateService extends UpdateService {
  final UpdateCheckStatus status;
  final ReleaseUpdateInfo? releaseInfo;
  final File? mockApkFile;
  final Future<bool> Function(String path)? onInstallApkCallback;

  _MockUpdateService({
    required this.status,
    this.releaseInfo,
    this.mockApkFile,
    this.onInstallApkCallback,
  }) : super(
         httpClient: MockClient((_) async => http.Response('', 200)),
         currentVersion: '1.0.0',
         onInstallApk: onInstallApkCallback,
       );

  @override
  Future<UpdateCheckResult> checkForUpdate({
    bool manual = false,
    String? skippedVersion,
    DateTime? lastCheckAt,
  }) async {
    return UpdateCheckResult(status: status, releaseInfo: releaseInfo);
  }

  @override
  Future<File?> downloadAndVerifyApk({
    required ReleaseUpdateInfo releaseInfo,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(1.0);
    return mockApkFile;
  }

  @override
  Future<bool> canRequestPackageInstalls() async => true;
}
