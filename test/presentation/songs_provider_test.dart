import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/presentation/providers/database_provider.dart';
import 'package:worship_setlist/presentation/providers/songs_provider.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('SongsProvider & SongsController', () {
    test('addSong validates URL and prevents duplicate entry', () async {
      final controller = container.read(songsControllerProvider.notifier);

      // 1. Add valid song
      final err1 = await controller.addSong(
        rawUrl: 'https://tabs.ultimate-guitar.com/tab/artist/song-1?utm=source',
        title: 'Song One',
        keyNote: 'C',
        notes: 'Verse 1 slow',
      );
      expect(err1, isNull);

      // 2. Attempt invalid URL
      final errInvalid = await controller.addSong(
        rawUrl: 'http://not-ug.com/tab/song',
        title: 'Invalid',
      );
      expect(errInvalid, isNotNull);
      expect(errInvalid, contains('HTTPS is required'));

      // 3. Attempt duplicate URL (with different query param or fragment)
      final errDuplicate = await controller.addSong(
        rawUrl: 'https://tabs.ultimate-guitar.com/tab/artist/song-1#chorus',
        title: 'Song One Duplicate',
      );
      expect(errDuplicate, isNotNull);
      expect(errDuplicate, contains('already exists as "Song One"'));
    });

    test('search query filters active songs by title', () async {
      final controller = container.read(songsControllerProvider.notifier);

      final sub = container.listen(filteredSongsProvider, (prev, next) {});

      await controller.addSong(
        rawUrl: 'https://tabs.ultimate-guitar.com/tab/hillsong/what-a-beautiful-name-1',
        title: 'What A Beautiful Name',
      );
      await controller.addSong(
        rawUrl: 'https://tabs.ultimate-guitar.com/tab/bethel/goodness-of-god-2',
        title: 'Goodness of God',
      );

      // Wait for stream to deliver the 2 songs
      for (var i = 0; i < 50; i++) {
        if ((container.read(filteredSongsProvider).value?.length ?? 0) == 2) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // Initial filter: all 2 songs
      var filtered = container.read(filteredSongsProvider).value;
      expect(filtered?.length, 2);

      // Apply search query
      container.read(songSearchQueryProvider.notifier).setQuery('beautiful');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      filtered = container.read(filteredSongsProvider).value;
      expect(filtered?.length, 1);
      expect(filtered?.first.title, 'What A Beautiful Name');

      sub.close();
    });

    test(
      'archiveSong removes song from active list but retains data in DB',
      () async {
        final controller = container.read(songsControllerProvider.notifier);

        final sub = container.listen(filteredSongsProvider, (prev, next) {});

        await controller.addSong(
          rawUrl: 'https://tabs.ultimate-guitar.com/tab/artist/song-archived-1',
          title: 'To Archive',
        );

        for (var i = 0; i < 50; i++) {
          if ((container.read(filteredSongsProvider).value?.length ?? 0) == 1) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }

        final songs = container.read(filteredSongsProvider).value;
        expect(songs?.length, 1);
        final songId = songs!.first.id;

        // Archive
        final success = await controller.archiveSong(songId);
        expect(success, isTrue);

        for (var i = 0; i < 50; i++) {
          if ((container.read(filteredSongsProvider).value?.length ?? 1) == 0) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }

        final afterArchive = container.read(filteredSongsProvider).value;
        expect(afterArchive?.isEmpty, isTrue);

        // Verify song is still in DB with archived = true
        final dbSong = await db.getSongById(songId);
        expect(dbSong?.archived, isTrue);

        sub.close();
      },
    );
  });
}
