import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/main.dart';
import 'package:worship_setlist/presentation/providers/database_provider.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Widget createSubject() {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const WorshipSetlistApp(),
    );
  }

  Future<void> tearDownWidget(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('Playlists & Home Navigation Flow', () {
    testWidgets('launches into Playlists tab and shows empty state', (
      tester,
    ) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      expect(find.text('Playlists'), findsWidgets);
      expect(find.text('No playlists yet'), findsOneWidget);
      expect(find.byKey(const Key('playlists_fab_add')), findsOneWidget);

      await tearDownWidget(tester);
    });

    testWidgets('switches between Playlists and Song Library tabs', (
      tester,
    ) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Switch to Song Library
      await tester.tap(find.byKey(const Key('nav_songs_tab')));
      await tester.pumpAndSettle();

      expect(find.text('Song Library'), findsWidgets);
      expect(find.text('Your song library is empty.'), findsOneWidget);

      // Switch back to Playlists
      await tester.tap(find.byKey(const Key('nav_playlists_tab')));
      await tester.pumpAndSettle();

      expect(find.text('No playlists yet'), findsOneWidget);

      await tearDownWidget(tester);
    });

    testWidgets('creates a new playlist from dialog and displays in list', (
      tester,
    ) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('playlists_fab_add')));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AlertDialog, 'New Playlist'), findsOneWidget);

      // Enter name
      await tester.enterText(
        find.byKey(const Key('create_playlist_name_field')),
        'Easter Sunday Worship',
      );

      await tester.tap(find.byKey(const Key('create_playlist_submit_button')));
      await tester.pumpAndSettle();

      // Verify playlist appears in the list
      expect(find.text('Easter Sunday Worship'), findsOneWidget);
      expect(find.text('0 songs'), findsOneWidget);

      await tearDownWidget(tester);
    });

    testWidgets('opens playlist detail screen, adds songs, and displays them', (
      tester,
    ) async {
      // Seed song in library
      await db.insertSong(
        title: 'Way Maker',
        url: 'https://tabs.ultimate-guitar.com/tab/sinach/way-maker-1',
        keyNote: 'E',
      );

      // Seed playlist
      await db.createPlaylist(
        name: 'Sunday Morning Set',
        serviceDate: DateTime(2026, 11, 29),
      );

      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Tap on playlist card
      await tester.tap(find.text('Sunday Morning Set'));
      await tester.pumpAndSettle();

      expect(find.text('Setlist is empty'), findsOneWidget);
      expect(find.byKey(const Key('start_service_button')), findsOneWidget);

      // Tap Add Songs
      await tester.tap(find.byKey(const Key('add_songs_empty_button')));
      await tester.pumpAndSettle();

      expect(find.text('Add Songs to Playlist'), findsOneWidget);
      expect(find.text('Way Maker'), findsOneWidget);

      // Select Way Maker checkbox
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();

      // Confirm Add
      await tester.tap(find.byKey(const Key('song_picker_confirm_button')));
      await tester.pumpAndSettle();

      // Verify song appears in setlist with position number and key chip
      expect(find.text('Way Maker'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('E'), findsOneWidget);
      expect(find.text('1 song in setlist'), findsOneWidget);

      await tearDownWidget(tester);
    });
  });
}
