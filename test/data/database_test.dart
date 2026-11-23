import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_setlist/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Songs Table & Queries', () {
    test(
      'insertSong creates a song with defaults and retrieval by ID/URL works',
      () async {
        final id = await db.insertSong(
          title: 'Amazing Grace',
          url: 'https://tabs.ultimate-guitar.com/tab/john-newton/amazing-grace-chords-12345',
          notes: 'Capo 2, slow tempo',
          keyNote: 'G',
        );

        final song = await db.getSongById(id);
        expect(song, isNotNull);
        expect(song!.title, 'Amazing Grace');
        expect(
          song.url,
          'https://tabs.ultimate-guitar.com/tab/john-newton/amazing-grace-chords-12345',
        );
        expect(song.notes, 'Capo 2, slow tempo');
        expect(song.keyNote, 'G');
        expect(song.archived, isFalse);

        final byUrl = await db.findSongByUrl(song.url);
        expect(byUrl?.id, id);
      },
    );

    test(
      'archiveSong soft-deletes the song without removing it from the database',
      () async {
        final id = await db.insertSong(
          title: 'Cornerstone',
          url: 'https://tabs.ultimate-guitar.com/tab/hillsong/cornerstone-123',
        );

        final initialActive = await db.getActiveSongs();
        expect(initialActive.any((s) => s.id == id), isTrue);

        final archived = await db.archiveSong(id);
        expect(archived, isTrue);

        final afterArchive = await db.getActiveSongs();
        expect(afterArchive.any((s) => s.id == id), isFalse);

        // Still retrievable by ID and URL (for history and duplicate detection)
        final directFetch = await db.getSongById(id);
        expect(directFetch, isNotNull);
        expect(directFetch!.archived, isTrue);

        // Restore
        await db.restoreSong(id);
        final restored = await db.getActiveSongs();
        expect(restored.any((s) => s.id == id), isTrue);
      },
    );
  });

  group('Playlists & Playlist Items (Transactions & Renormalization)', () {
    test('create, duplicate, and delete playlists', () async {
      final sunday = DateTime(2026, 11, 29);
      final playlistId = await db.createPlaylist(
        name: 'Sunday Morning',
        serviceDate: sunday,
      );

      final song1 = await db.insertSong(
        title: 'Song 1',
        url: 'https://tabs.ultimate-guitar.com/tab/artist/song-1',
      );
      final song2 = await db.insertSong(
        title: 'Song 2',
        url: 'https://tabs.ultimate-guitar.com/tab/artist/song-2',
      );

      await db.addSongToPlaylist(playlistId: playlistId, songId: song1);
      await db.addSongToPlaylist(playlistId: playlistId, songId: song2);

      final items = await db.getPlaylistItemsWithSong(playlistId);
      expect(items.length, 2);
      expect(items[0].item.position, 0);
      expect(items[1].item.position, 1);

      // Duplicate playlist (Copy as new Sunday)
      final nextSunday = DateTime(2026, 12, 6);
      final dupId = await db.duplicatePlaylist(
        sourcePlaylistId: playlistId,
        newName: 'Next Sunday',
        newServiceDate: nextSunday,
      );

      final dupItems = await db.getPlaylistItemsWithSong(dupId);
      expect(dupItems.length, 2);
      expect(dupItems[0].item.position, 0);
      expect(dupItems[1].item.position, 1);
      expect(dupItems[0].song.title, 'Song 1');

      // Delete original playlist cascades to items, but songs remain
      await db.deletePlaylist(playlistId);
      final itemsAfterDelete = await db.getPlaylistItemsWithSong(playlistId);
      expect(itemsAfterDelete.isEmpty, isTrue);

      final survivingSong = await db.getSongById(song1);
      expect(survivingSong, isNotNull);
    });

    test(
      'addSongToPlaylist allows duplicate songs with contiguous positions',
      () async {
        final playlistId = await db.createPlaylist(
          name: 'Service',
          serviceDate: DateTime(2026, 11, 29),
        );
        final songId = await db.insertSong(
          title: 'Repeated Song',
          url: 'https://tabs.ultimate-guitar.com/tab/artist/repeated',
        );

        await db.addSongToPlaylist(playlistId: playlistId, songId: songId);
        await db.addSongToPlaylist(playlistId: playlistId, songId: songId);

        final items = await db.getPlaylistItemsWithSong(playlistId);
        expect(items.length, 2);
        expect(items[0].item.songId, songId);
        expect(items[0].item.position, 0);
        expect(items[1].item.songId, songId);
        expect(items[1].item.position, 1);
      },
    );

    test('removePlaylistItem removes item and renormalizes remaining items to 0..n-1', () async {
      final playlistId = await db.createPlaylist(
        name: 'Service',
        serviceDate: DateTime(2026, 11, 29),
      );
      final song1 = await db.insertSong(
        title: 'S1',
        url: 'https://tabs.ultimate-guitar.com/tab/a/1',
      );
      final song2 = await db.insertSong(
        title: 'S2',
        url: 'https://tabs.ultimate-guitar.com/tab/a/2',
      );
      final song3 = await db.insertSong(
        title: 'S3',
        url: 'https://tabs.ultimate-guitar.com/tab/a/3',
      );

      final item1Id = await db.addSongToPlaylist(
        playlistId: playlistId,
        songId: song1,
      );
      final item2Id = await db.addSongToPlaylist(
        playlistId: playlistId,
        songId: song2,
      );
      final item3Id = await db.addSongToPlaylist(
        playlistId: playlistId,
        songId: song3,
      );

      // Remove middle item (item2)
      await db.removePlaylistItem(item2Id);

      final remaining = await db.getPlaylistItemsWithSong(playlistId);
      expect(remaining.length, 2);
      expect(remaining[0].item.id, item1Id);
      expect(remaining[0].item.position, 0);
      expect(remaining[1].item.id, item3Id);
      expect(remaining[1].item.position, 1); // Renormalized from 2 to 1!
    });

    test('reorderPlaylistItems updates positions atomically', () async {
      final playlistId = await db.createPlaylist(
        name: 'Service',
        serviceDate: DateTime(2026, 11, 29),
      );
      final s1 = await db.insertSong(
        title: 'S1',
        url: 'https://tabs.ultimate-guitar.com/tab/a/1',
      );
      final s2 = await db.insertSong(
        title: 'S2',
        url: 'https://tabs.ultimate-guitar.com/tab/a/2',
      );
      final s3 = await db.insertSong(
        title: 'S3',
        url: 'https://tabs.ultimate-guitar.com/tab/a/3',
      );

      final i1 = await db.addSongToPlaylist(playlistId: playlistId, songId: s1);
      final i2 = await db.addSongToPlaylist(playlistId: playlistId, songId: s2);
      final i3 = await db.addSongToPlaylist(playlistId: playlistId, songId: s3);

      // Reverse order: i3, i2, i1
      await db.reorderPlaylistItems(playlistId, [i3, i2, i1]);

      final reordered = await db.getPlaylistItemsWithSong(playlistId);
      expect(reordered[0].item.id, i3);
      expect(reordered[0].item.position, 0);
      expect(reordered[1].item.id, i2);
      expect(reordered[1].item.position, 1);
      expect(reordered[2].item.id, i1);
      expect(reordered[2].item.position, 2);
    });
  });

  group('AppSettings Table & Operations', () {
    test(
      'getOrCreateSettings provides initial row and updates persist',
      () async {
        final settings = await db.getOrCreateSettings();
        expect(settings.id, 1);
        expect(settings.lastUpdateCheck, isNull);

        final now = DateTime(2026, 11, 23, 10, 0);
        await db.updateSettings(
          lastUpdateCheck: now,
          skippedVersion: '1.2.0',
          lastBackupAt: now,
        );

        final updated = await db.getOrCreateSettings();
        expect(updated.lastUpdateCheck, now);
        expect(updated.skippedVersion, '1.2.0');
        expect(updated.lastBackupAt, now);
      },
    );
  });
}
