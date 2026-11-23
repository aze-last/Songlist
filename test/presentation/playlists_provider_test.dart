import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/domain/date_utils.dart';
import 'package:worship_setlist/presentation/providers/database_provider.dart';
import 'package:worship_setlist/presentation/providers/playlists_provider.dart';

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

  group('PlaylistsProvider & PlaylistsController', () {
    test('createPlaylist adds a new playlist and emits via playlistsStreamProvider', () async {
      final controller = container.read(playlistsControllerProvider.notifier);
      final sub = container.listen(playlistsStreamProvider, (prev, next) {});

      final sunday = ServiceDateUtils.getNextSunday();
      final id = await controller.createPlaylist(
        name: 'Sunday Worship',
        serviceDate: sunday,
      );
      expect(id, isPositive);

      for (var i = 0; i < 50; i++) {
        if ((container.read(playlistsStreamProvider).value?.length ?? 0) == 1) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final playlists = container.read(playlistsStreamProvider).value;
      expect(playlists?.length, 1);
      expect(playlists?.first.name, 'Sunday Worship');
      expect(playlists?.first.serviceDate, sunday);

      sub.close();
    });

    test(
      'addSongsToPlaylist adds multiple songs with contiguous positions',
      () async {
        final controller = container.read(playlistsControllerProvider.notifier);
        final sunday = ServiceDateUtils.getNextSunday();
        final playlistId = await controller.createPlaylist(
          name: 'Service Nov 29',
          serviceDate: sunday,
        );

        final s1 = await db.insertSong(
          title: 'Song 1',
          url: 'https://tabs.ultimate-guitar.com/tab/a/1',
        );
        final s2 = await db.insertSong(
          title: 'Song 2',
          url: 'https://tabs.ultimate-guitar.com/tab/a/2',
        );

        final sub = container.listen(
          playlistItemsStreamProvider(playlistId),
          (prev, next) {},
        );

        await controller.addSongsToPlaylist(
          playlistId: playlistId,
          songIds: [s1, s2],
        );

        for (var i = 0; i < 50; i++) {
          if ((container
                      .read(playlistItemsStreamProvider(playlistId))
                      .value
                      ?.length ??
                  0) ==
              2) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }

        final items = container
            .read(playlistItemsStreamProvider(playlistId))
            .value;
        expect(items?.length, 2);
        expect(items?[0].item.position, 0);
        expect(items?[1].item.position, 1);
        expect(items?[0].song.title, 'Song 1');
        expect(items?[1].song.title, 'Song 2');

        sub.close();
      },
    );

    test(
      'duplicatePlaylist creates a copy with items under new date',
      () async {
        final controller = container.read(playlistsControllerProvider.notifier);
        final s1 = DateTime(2026, 11, 29);
        final s2 = DateTime(2026, 12, 6);

        final originalId = await controller.createPlaylist(
          name: 'Nov 29 Service',
          serviceDate: s1,
        );
        final songId = await db.insertSong(
          title: 'Song 1',
          url: 'https://tabs.ultimate-guitar.com/tab/a/1',
        );
        await controller.addSongsToPlaylist(
          playlistId: originalId,
          songIds: [songId],
        );

        final dupId = await controller.duplicatePlaylist(
          sourcePlaylistId: originalId,
          newName: 'Dec 6 Service',
          newServiceDate: s2,
        );

        final dupItems = await db.getPlaylistItemsWithSong(dupId);
        expect(dupItems.length, 1);
        expect(dupItems.first.song.title, 'Song 1');
        expect(dupItems.first.item.position, 0);
      },
    );

    test('deletePlaylist removes playlist and its items', () async {
      final controller = container.read(playlistsControllerProvider.notifier);
      final pid = await controller.createPlaylist(
        name: 'To Delete',
        serviceDate: DateTime(2026, 11, 29),
      );
      final songId = await db.insertSong(
        title: 'Song 1',
        url: 'https://tabs.ultimate-guitar.com/tab/a/1',
      );
      await controller.addSongsToPlaylist(playlistId: pid, songIds: [songId]);

      await controller.deletePlaylist(pid);

      final pl = await db.getPlaylistById(pid);
      expect(pl, isNull);
      final items = await db.getPlaylistItemsWithSong(pid);
      expect(items.isEmpty, isTrue);
      // Song remains in database
      final song = await db.getSongById(songId);
      expect(song, isNotNull);
    });
  });
}
