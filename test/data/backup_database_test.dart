import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/data/services/backup_service.dart';
import 'package:worship_setlist/domain/backup_manager.dart';

void main() {
  late AppDatabase db;
  late BackupService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = BackupService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Backup & Restore Database Operations (spec.md Section 6 & 10)', () {
    test('exports database records to valid backup JSON string', () async {
      // Seed songs
      final s1 = await db.insertSong(
        title: 'Mighty To Save',
        url: 'https://tabs.ultimate-guitar.com/tab/hillsong/mighty-to-save-1',
        keyNote: 'A',
        notes: 'Lead guitar intro',
      );
      final s2 = await db.insertSong(
        title: 'Goodness of God',
        url: 'https://tabs.ultimate-guitar.com/tab/bethel/goodness-of-god-2',
        keyNote: 'G',
      );

      // Seed playlist
      final p1 = await db.createPlaylist(
        name: 'Sunday Morning Service',
        serviceDate: DateTime(2026, 11, 29),
      );

      // Add songs to playlist
      await db.addSongToPlaylist(playlistId: p1, songId: s1);
      await db.addSongToPlaylist(playlistId: p1, songId: s2);

      // Generate JSON
      final jsonStr = await service.generateBackupJson();
      final validation = BackupManager.validateAndParse(jsonStr);

      expect(validation.isValid, isTrue);
      final payload = validation.payload!;
      expect(payload.schemaVersion, equals(1));
      expect(payload.songs.length, equals(2));
      expect(payload.playlists.length, equals(1));
      expect(payload.playlistItems.length, equals(2));
      expect(payload.playlistItems[0].position, equals(0));
      expect(payload.playlistItems[1].position, equals(1));
    });

    test('restores database completely from backup payload and updates lastBackupAt', () async {
      // 1. Initial State: 2 songs, 1 playlist with 2 items
      final s1 = await db.insertSong(
        title: 'Song 1',
        url: 'https://tabs.ultimate-guitar.com/tab/s1',
        keyNote: 'C',
      );
      final s2 = await db.insertSong(
        title: 'Song 2',
        url: 'https://tabs.ultimate-guitar.com/tab/s2',
        keyNote: 'D',
      );
      final p1 = await db.createPlaylist(
        name: 'Nov 29 Setlist',
        serviceDate: DateTime(2026, 11, 29),
      );
      await db.addSongToPlaylist(playlistId: p1, songId: s1);
      await db.addSongToPlaylist(playlistId: p1, songId: s2);

      // 2. Export Backup
      final jsonStr = await service.generateBackupJson();
      final validation = BackupManager.validateAndParse(jsonStr);
      expect(validation.isValid, isTrue);

      // 3. Mutate DB (simulate local changes/additions)
      await db.insertSong(
        title: 'Mutated Song 3',
        url: 'https://tabs.ultimate-guitar.com/tab/s3',
      );
      await db.createPlaylist(
        name: 'Mutated Playlist 2',
        serviceDate: DateTime(2026, 12, 6),
      );

      final songsBefore = await db.getAllSongs();
      expect(songsBefore.length, equals(3));
      final playlistsBefore = await db.getAllPlaylists();
      expect(playlistsBefore.length, equals(2));

      // 4. Restore original backup payload
      await service.restoreFromPayload(validation.payload!);

      // 5. Verify restored state matches original exactly
      final songsAfter = await db.getAllSongs();
      expect(songsAfter.length, equals(2));
      expect(songsAfter.map((s) => s.title), containsAll(['Song 1', 'Song 2']));
      expect(songsAfter.map((s) => s.title), isNot(contains('Mutated Song 3')));

      final playlistsAfter = await db.getAllPlaylists();
      expect(playlistsAfter.length, equals(1));
      expect(playlistsAfter.first.name, equals('Nov 29 Setlist'));

      final itemsAfter = await db.getAllPlaylistItems();
      expect(itemsAfter.length, equals(2));
      expect(itemsAfter[0].position, equals(0));
      expect(itemsAfter[1].position, equals(1));

      // Verify settings updated
      final settings = await db.getOrCreateSettings();
      expect(settings.lastBackupAt, isNotNull);
    });
  });
}
