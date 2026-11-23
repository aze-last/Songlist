import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/data/services/backup_service.dart';
import 'package:worship_setlist/domain/backup_manager.dart';
import 'package:worship_setlist/presentation/providers/database_provider.dart';
import 'package:worship_setlist/presentation/screens/settings/settings_screen.dart';
import 'package:worship_setlist/presentation/widgets/weekly_backup_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tempDir;

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'Worship Setlist',
      packageName: 'com.worship.setlist',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('songlist_test_');
  });

  tearDown(() async {
    await db.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Future<void> tearDownWidget(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  Widget createSubject({
    Future<String?> Function()? filePicker,
    Future<void> Function(String filePath)? shareHandler,
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        backupServiceProvider.overrideWithValue(
          BackupService(db, tempDirProvider: () async => tempDir),
        ),
      ],
      child: MaterialApp(
        home: SettingsScreen(
          filePicker: filePicker,
          shareHandler: shareHandler,
        ),
      ),
    );
  }

  group(
    'SettingsScreen & Backup/Restore UI Flow (spec.md Section 5.4 & 6)',
    () {
      testWidgets('renders all cards and shows Never for initial backup date', (
        tester,
      ) async {
        await tester.pumpWidget(createSubject());
        await tester.pumpAndSettle();

        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('Application Info'), findsOneWidget);
        expect(find.text('Backup & Restore'), findsOneWidget);
        expect(find.text('Updates'), findsOneWidget);

        expect(find.byKey(const Key('last_backup_date_text')), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('last_backup_date_text')))
              .data,
          equals('Never'),
        );

        await tearDownWidget(tester);
      });

      testWidgets(
        'exports backup, triggers share handler, and updates last backup date',
        (tester) async {
          // Seed 1 song
          await db.insertSong(
            title: 'Amazing Grace',
            url: 'https://tabs.ultimate-guitar.com/tab/john-newton/amazing-grace-1',
          );

          String? exportedFilePath;

          await tester.pumpWidget(
            createSubject(
              shareHandler: (filePath) async {
                exportedFilePath = filePath;
              },
            ),
          );
          await tester.pumpAndSettle();

          // Tap Export
          final exportBtn = find.byKey(const Key('export_backup_button'));
          await tester.ensureVisible(exportBtn);
          await tester.tap(exportBtn);
          for (var i = 0; i < 20 && exportedFilePath == null; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          await tester.pumpAndSettle();

          // Verify share handler was invoked with existing file
          expect(exportedFilePath, isNotNull);
          final file = File(exportedFilePath!);
          expect(file.existsSync(), isTrue);

          // Verify JSON payload
          final content = file.readAsStringSync();
          final validation = BackupManager.validateAndParse(content);
          expect(validation.isValid, isTrue);
          expect(
            validation.payload!.songs.first.title,
            equals('Amazing Grace'),
          );

          // Verify SnackBar
          expect(find.text('Backup exported successfully!'), findsOneWidget);

          await tearDownWidget(tester);
        },
      );

      testWidgets(
        'imports valid backup with confirmation dialog and restores data',
        (tester) async {
          // Create backup file to import
          final backupContent = BackupManager.formatBackupJson(
            songs: [
              BackupDataSong(
                id: 101,
                title: 'Imported Song 1',
                url: 'https://tabs.ultimate-guitar.com/tab/artist/song-1',
                createdAt: DateTime.now(),
              ),
              BackupDataSong(
                id: 102,
                title: 'Imported Song 2',
                url: 'https://tabs.ultimate-guitar.com/tab/artist/song-2',
                createdAt: DateTime.now(),
              ),
            ],
            playlists: [
              BackupDataPlaylist(
                id: 201,
                name: 'Imported Playlist',
                serviceDate: DateTime(2026, 12, 13),
                createdAt: DateTime.now(),
              ),
            ],
            playlistItems: [
              const BackupDataPlaylistItem(
                id: 1,
                playlistId: 201,
                songId: 101,
                position: 0,
              ),
            ],
          );

          final testBackupFile = File(p.join(tempDir.path, 'test_import.json'));
          testBackupFile.writeAsStringSync(backupContent);

          await tester.pumpWidget(
            createSubject(filePicker: () async => testBackupFile.path),
          );
          await tester.pumpAndSettle();

          // Tap Import Backup
          await tester.tap(find.byKey(const Key('import_backup_button')));
          for (
            var i = 0;
            i < 20 &&
                find
                    .byKey(const Key('confirm_restore_dialog'))
                    .evaluate()
                    .isEmpty;
            i++
          ) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          await tester.pumpAndSettle();

          // Confirmation dialog must appear
          expect(
            find.byKey(const Key('confirm_restore_dialog')),
            findsOneWidget,
          );
          expect(find.text('Replace Current Data?'), findsOneWidget);
          expect(find.textContaining('• 2 songs'), findsOneWidget);
          expect(find.textContaining('• 1 playlist'), findsOneWidget);

          // Cancel keeps existing data
          await tester.tap(find.byKey(const Key('cancel_restore_button')));
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('confirm_restore_dialog')), findsNothing);
          expect(await db.getAllSongs(), isEmpty);

          // Tap Import again and Confirm
          await tester.tap(find.byKey(const Key('import_backup_button')));
          for (
            var i = 0;
            i < 20 &&
                find
                    .byKey(const Key('confirm_restore_dialog'))
                    .evaluate()
                    .isEmpty;
            i++
          ) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const Key('confirm_replace_button')));
          for (var i = 0; i < 20 && (await db.getAllSongs()).isEmpty; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          await tester.pumpAndSettle();

          // Verify restore success
          final songs = await db.getAllSongs();
          expect(songs.length, equals(2));
          expect(
            songs.map((s) => s.title),
            containsAll(['Imported Song 1', 'Imported Song 2']),
          );

          final playlists = await db.getAllPlaylists();
          expect(playlists.length, equals(1));
          expect(playlists.first.name, equals('Imported Playlist'));

          await tearDownWidget(tester);
        },
      );

      testWidgets(
        'shows validation error dialog when importing corrupt or invalid file',
        (tester) async {
          final corruptFile = File(p.join(tempDir.path, 'corrupt.json'));
          corruptFile.writeAsStringSync('{"schema_version": 999}');

          await tester.pumpWidget(
            createSubject(filePicker: () async => corruptFile.path),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const Key('import_backup_button')));
          for (
            var i = 0;
            i < 20 &&
                find
                    .byKey(const Key('backup_validation_error_dialog'))
                    .evaluate()
                    .isEmpty;
            i++
          ) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          await tester.pumpAndSettle();

          // Validation error dialog appears
          expect(
            find.byKey(const Key('backup_validation_error_dialog')),
            findsOneWidget,
          );
          expect(find.text('Invalid Backup File'), findsOneWidget);
          expect(
            find.textContaining('Unsupported backup schema version: 999'),
            findsOneWidget,
          );

          await tearDownWidget(tester);
        },
      );
    },
  );

  group('WeeklyBackupBanner Widget', () {
    testWidgets('shows banner when lastBackupAt is null and allows dismissal', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(
            home: Scaffold(body: Column(children: [WeeklyBackupBanner()])),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Banner is visible
      expect(find.byKey(const Key('weekly_backup_banner')), findsOneWidget);
      expect(find.text('Weekly Backup Reminder'), findsOneWidget);

      // Dismiss banner
      await tester.tap(find.byKey(const Key('banner_dismiss_button')));
      await tester.pumpAndSettle();

      // Banner is dismissed
      expect(find.byKey(const Key('weekly_backup_banner')), findsNothing);

      await tearDownWidget(tester);
    });

    testWidgets('does not show banner when backup was made today', (
      tester,
    ) async {
      await db.updateSettings(lastBackupAt: DateTime.now());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(
            home: Scaffold(body: Column(children: [WeeklyBackupBanner()])),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('weekly_backup_banner')), findsNothing);

      await tearDownWidget(tester);
    });
  });
}
