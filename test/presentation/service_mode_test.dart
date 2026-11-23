import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/presentation/providers/database_provider.dart';
import 'package:worship_setlist/presentation/providers/service_provider.dart';
import 'package:worship_setlist/presentation/screens/playlists/playlist_detail_screen.dart';
import 'package:worship_setlist/presentation/screens/service/service_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<PlaylistItemWithSong> mockItems;

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    mockItems = [
      PlaylistItemWithSong(
        item: const PlaylistItem(id: 1, playlistId: 1, songId: 1, position: 0),
        song: Song(
          id: 1,
          title: '10,000 Reasons',
          url: 'https://tabs.ultimate-guitar.com/tab/matt-redman/10000-reasons-1',
          keyNote: 'G',
          notes: 'Acoustic intro, 4 bars',
          createdAt: DateTime.now(),
          archived: false,
        ),
      ),
      PlaylistItemWithSong(
        item: const PlaylistItem(id: 2, playlistId: 1, songId: 2, position: 1),
        song: Song(
          id: 2,
          title: 'Oceans',
          url: 'https://tabs.ultimate-guitar.com/tab/hillsong/oceans-2',
          keyNote: 'D',
          notes: 'Key change at bridge',
          createdAt: DateTime.now(),
          archived: false,
        ),
      ),
      PlaylistItemWithSong(
        item: const PlaylistItem(id: 3, playlistId: 1, songId: 3, position: 2),
        song: Song(
          id: 3,
          title: 'Way Maker',
          url: 'https://tabs.ultimate-guitar.com/tab/leeland/way-maker-3',
          keyNote: 'E',
          notes: 'Drums enter verse 2',
          createdAt: DateTime.now(),
          archived: false,
        ),
      ),
    ];
  });

  Widget createServiceSubject({
    int initialIndex = 0,
    ServiceController? controller,
  }) {
    return MaterialApp(
      home: ServiceScreen(
        playlistId: 1,
        items: mockItems,
        initialIndex: initialIndex,
        controller: controller,
        webViewBuilder: (context, url) => Container(
          key: const Key('mock_webview'),
          child: Text('Current URL: $url'),
        ),
      ),
    );
  }

  Future<void> tearDownWidget(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('ServiceScreen Navigation & Core Interactions (spec.md Section 5.3)', () {
    testWidgets('renders first song and enforces boundary button states', (
      tester,
    ) async {
      await tester.pumpWidget(createServiceSubject());
      await tester.pumpAndSettle();

      // Song 1 rendered
      expect(find.text('1 of 3'), findsOneWidget);
      expect(find.text('10,000 Reasons'), findsOneWidget);
      expect(
        find.text(
          'Current URL: https://tabs.ultimate-guitar.com/tab/matt-redman/10000-reasons-1',
        ),
        findsOneWidget,
      );

      // Previous button must be disabled at position 0
      final prevBtn = tester.widget<FilledButton>(
        find.byKey(const Key('service_prev_button')),
      );
      expect(prevBtn.onPressed, isNull);

      // Next button must be enabled
      final nextBtn = tester.widget<FilledButton>(
        find.byKey(const Key('service_next_button')),
      );
      expect(nextBtn.onPressed, isNotNull);

      await tearDownWidget(tester);
    });

    testWidgets('navigates forward and backward with Next and Prev buttons', (
      tester,
    ) async {
      await tester.pumpWidget(createServiceSubject());
      await tester.pumpAndSettle();

      // Tap Next to move to Song 2
      await tester.tap(find.byKey(const Key('service_next_button')));
      await tester.pumpAndSettle();

      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text('Oceans'), findsOneWidget);
      expect(
        find.text(
          'Current URL: https://tabs.ultimate-guitar.com/tab/hillsong/oceans-2',
        ),
        findsOneWidget,
      );

      // Both Prev and Next should be enabled
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('service_prev_button')))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('service_next_button')))
            .onPressed,
        isNotNull,
      );

      // Tap Next to move to Song 3 (last song)
      await tester.tap(find.byKey(const Key('service_next_button')));
      await tester.pumpAndSettle();

      expect(find.text('3 of 3'), findsOneWidget);
      expect(find.text('Way Maker'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);

      // Next should now be disabled
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('service_next_button')))
            .onPressed,
        isNull,
      );

      // Tap Prev to go back to Song 2
      await tester.tap(find.byKey(const Key('service_prev_button')));
      await tester.pumpAndSettle();

      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text('Oceans'), findsOneWidget);

      await tearDownWidget(tester);
    });

    testWidgets('opens jump list and navigates directly to selected song', (
      tester,
    ) async {
      await tester.pumpWidget(createServiceSubject());
      await tester.pumpAndSettle();

      // Tap center title button to open jump list
      await tester.tap(find.byKey(const Key('service_title_jump_button')));
      await tester.pumpAndSettle();

      // Verify jump list sheet opened
      expect(find.text('Jump to Song'), findsOneWidget);
      expect(find.text('3 total'), findsOneWidget);

      // Select Song 3 ("Way Maker")
      await tester.tap(find.byKey(const Key('jump_list_item_2')));
      await tester.pumpAndSettle();

      // Sheet closed, now displaying Song 3
      expect(find.text('Jump to Song'), findsNothing);
      expect(find.text('3 of 3'), findsOneWidget);
      expect(find.text('Way Maker'), findsOneWidget);
      expect(
        find.text(
          'Current URL: https://tabs.ultimate-guitar.com/tab/leeland/way-maker-3',
        ),
        findsOneWidget,
      );

      await tearDownWidget(tester);
    });

    testWidgets('expands and collapses notes panel', (tester) async {
      await tester.pumpWidget(createServiceSubject());
      await tester.pumpAndSettle();

      // Key note badge is visible
      expect(find.text('G'), findsOneWidget);

      // Notes panel toggle
      await tester.tap(find.byKey(const Key('notes_panel_toggle_bar')));
      await tester.pumpAndSettle();

      // Expanded notes content visible
      expect(find.text('Acoustic intro, 4 bars'), findsWidgets);

      // Tap again to collapse
      await tester.tap(find.byKey(const Key('notes_panel_toggle_bar')));
      await tester.pumpAndSettle();

      await tearDownWidget(tester);
    });

    testWidgets('intercepts exit with confirmation dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_service_button'),
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => ServiceScreen(
                        playlistId: 1,
                        items: mockItems,
                        webViewBuilder: (context, url) =>
                            Text('Current URL: $url'),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Service Mode
      await tester.tap(find.byKey(const Key('open_service_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('service_exit_button')), findsOneWidget);

      // Tap Exit button
      await tester.tap(find.byKey(const Key('service_exit_button')));
      await tester.pumpAndSettle();

      // Dialog appears
      expect(find.byKey(const Key('leave_service_dialog')), findsOneWidget);
      expect(find.text('Leave Service Mode?'), findsOneWidget);

      // Cancel leaves user in Service Mode
      await tester.tap(find.byKey(const Key('cancel_leave_service_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('leave_service_dialog')), findsNothing);
      expect(find.byKey(const Key('service_exit_button')), findsOneWidget);

      // Tap Exit button again, then Confirm Leave
      await tester.tap(find.byKey(const Key('service_exit_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirm_leave_service_button')));
      await tester.pumpAndSettle();

      // Returned to home screen
      expect(find.byKey(const Key('open_service_button')), findsOneWidget);

      await tearDownWidget(tester);
    });
  });

  group('Start Service & Resume Position Integration', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('prompts to resume when saved position exists > 0', (
      tester,
    ) async {
      // Seed DB with 1 playlist and 3 songs
      final pId = await db
          .into(db.playlists)
          .insert(
            PlaylistsCompanion.insert(
              name: 'Sunday Morning',
              serviceDate: DateTime(2026, 11, 29),
            ),
          );

      final s1 = await db
          .into(db.songs)
          .insert(
            SongsCompanion.insert(
              title: 'Song 1',
              url: 'https://tabs.ultimate-guitar.com/tab/s1',
            ),
          );
      final s2 = await db
          .into(db.songs)
          .insert(
            SongsCompanion.insert(
              title: 'Song 2',
              url: 'https://tabs.ultimate-guitar.com/tab/s2',
            ),
          );
      final s3 = await db
          .into(db.songs)
          .insert(
            SongsCompanion.insert(
              title: 'Song 3',
              url: 'https://tabs.ultimate-guitar.com/tab/s3',
            ),
          );

      await db
          .into(db.playlistItems)
          .insert(
            PlaylistItemsCompanion.insert(
              playlistId: pId,
              songId: s1,
              position: 0,
            ),
          );
      await db
          .into(db.playlistItems)
          .insert(
            PlaylistItemsCompanion.insert(
              playlistId: pId,
              songId: s2,
              position: 1,
            ),
          );
      await db
          .into(db.playlistItems)
          .insert(
            PlaylistItemsCompanion.insert(
              playlistId: pId,
              songId: s3,
              position: 2,
            ),
          );

      // Set saved position at song index 1 (Song 2)
      SharedPreferences.setMockInitialValues({'playlist_last_pos_$pId': 1});

      final playlist = await (db.select(
        db.playlists,
      )..where((t) => t.id.equals(pId))).getSingle();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(home: PlaylistDetailScreen(playlist: playlist)),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Start Service
      await tester.tap(find.byKey(const Key('start_service_button')));
      await tester.pumpAndSettle();

      // Resume dialog appears
      expect(find.byKey(const Key('resume_service_dialog')), findsOneWidget);
      expect(
        find.text('Resume from song 2 ("Song 2") or start from the beginning?'),
        findsOneWidget,
      );

      // Tap Resume
      await tester.tap(find.byKey(const Key('resume_dialog_resume_button')));
      await tester.pumpAndSettle();

      // Verifies launched at index 1 ("2 of 3", Song 2)
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text('Song 2'), findsOneWidget);

      await tearDownWidget(tester);
    });

    testWidgets(
      'starts at beginning when user chooses "Start from Beginning"',
      (tester) async {
        final pId = await db
            .into(db.playlists)
            .insert(
              PlaylistsCompanion.insert(
                name: 'Sunday Morning',
                serviceDate: DateTime(2026, 11, 29),
              ),
            );

        final s1 = await db
            .into(db.songs)
            .insert(
              SongsCompanion.insert(
                title: 'First Song',
                url: 'https://tabs.ultimate-guitar.com/tab/s1',
              ),
            );
        final s2 = await db
            .into(db.songs)
            .insert(
              SongsCompanion.insert(
                title: 'Second Song',
                url: 'https://tabs.ultimate-guitar.com/tab/s2',
              ),
            );

        await db
            .into(db.playlistItems)
            .insert(
              PlaylistItemsCompanion.insert(
                playlistId: pId,
                songId: s1,
                position: 0,
              ),
            );
        await db
            .into(db.playlistItems)
            .insert(
              PlaylistItemsCompanion.insert(
                playlistId: pId,
                songId: s2,
                position: 1,
              ),
            );

        // Set saved position at song index 1
        SharedPreferences.setMockInitialValues({'playlist_last_pos_$pId': 1});

        final playlist = await (db.select(
          db.playlists,
        )..where((t) => t.id.equals(pId))).getSingle();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(home: PlaylistDetailScreen(playlist: playlist)),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Start Service
        await tester.tap(find.byKey(const Key('start_service_button')));
        await tester.pumpAndSettle();

        // Resume dialog appears -> Tap "Start from Beginning"
        expect(find.byKey(const Key('resume_service_dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('resume_dialog_restart_button')));
        await tester.pumpAndSettle();

        // Verifies launched at index 0 ("1 of 2", First Song)
        expect(find.text('1 of 2'), findsOneWidget);
        expect(find.text('First Song'), findsOneWidget);

        await tearDownWidget(tester);
      },
    );
  });
}
