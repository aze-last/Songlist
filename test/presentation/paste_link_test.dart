import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/presentation/providers/database_provider.dart';
import 'package:worship_setlist/presentation/screens/songs/paste_link_dialog.dart';

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
      child: const MaterialApp(home: Scaffold(body: PasteLinkDialog())),
    );
  }

  group('PasteLinkDialog', () {
    testWidgets('shows validation errors when fields are empty', (
      tester,
    ) async {
      await tester.pumpWidget(createSubject());

      await tester.tap(find.byKey(const Key('paste_link_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a URL.'), findsOneWidget);
      expect(find.text('Please enter a title.'), findsOneWidget);
    });

    testWidgets('shows validation error for non-UG or non-HTTPS URL', (
      tester,
    ) async {
      await tester.pumpWidget(createSubject());

      await tester.enterText(
        find.byKey(const Key('paste_link_url_field')),
        'http://example.com/tab/1',
      );
      await tester.enterText(
        find.byKey(const Key('paste_link_title_field')),
        'Test Song',
      );

      await tester.tap(find.byKey(const Key('paste_link_submit_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('HTTPS is required'), findsOneWidget);
    });

    testWidgets('successfully submits valid song and adds to database', (
      tester,
    ) async {
      await tester.pumpWidget(createSubject());

      await tester.enterText(
        find.byKey(const Key('paste_link_url_field')),
        'https://tabs.ultimate-guitar.com/tab/artist/song-1',
      );
      await tester.enterText(
        find.byKey(const Key('paste_link_title_field')),
        'Grace Alone',
      );
      await tester.enterText(
        find.byKey(const Key('paste_link_keynote_field')),
        'E major',
      );

      await tester.tap(find.byKey(const Key('paste_link_submit_button')));
      await tester.pumpAndSettle();

      final songs = await db.getActiveSongs();
      expect(songs.length, 1);
      expect(songs.first.title, 'Grace Alone');
      expect(songs.first.keyNote, 'E major');
    });

    testWidgets(
      'displays duplicate error banner when song URL already exists',
      (tester) async {
        // Pre-seed database with a song
        await db.insertSong(
          title: 'Original Song',
          url: 'https://tabs.ultimate-guitar.com/tab/artist/existing-song',
        );

        await tester.pumpWidget(createSubject());

        // Attempt to add duplicate
        await tester.enterText(
          find.byKey(const Key('paste_link_url_field')),
          'https://tabs.ultimate-guitar.com/tab/artist/existing-song?utm_source=app',
        );
        await tester.enterText(
          find.byKey(const Key('paste_link_title_field')),
          'Duplicate Name',
        );

        await tester.tap(find.byKey(const Key('paste_link_submit_button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('paste_link_error_banner')),
          findsOneWidget,
        );
        expect(
          find.textContaining('already exists as "Original Song"'),
          findsOneWidget,
        );
      },
    );
  });
}
