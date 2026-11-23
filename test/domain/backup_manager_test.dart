import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:worship_setlist/domain/backup_manager.dart';

void main() {
  group('BackupManager Domain Logic (spec.md Section 6 & 10)', () {
    final now = DateTime(2026, 11, 23, 10, 30);

    final sampleSongs = [
      BackupDataSong(
        id: 1,
        title: '10,000 Reasons',
        url: 'https://tabs.ultimate-guitar.com/tab/matt-redman/10000-reasons-1',
        notes: 'Capo 2',
        keyNote: 'G',
        createdAt: DateTime(2026, 11, 1),
        archived: false,
      ),
      BackupDataSong(
        id: 2,
        title: 'Oceans',
        url: 'https://tabs.ultimate-guitar.com/tab/hillsong/oceans-2',
        notes: null,
        keyNote: 'D',
        createdAt: DateTime(2026, 11, 2),
        archived: true,
      ),
    ];

    final samplePlaylists = [
      BackupDataPlaylist(
        id: 1,
        name: 'Sunday Worship Nov 29',
        serviceDate: DateTime(2026, 11, 29),
        createdAt: DateTime(2026, 11, 15),
      ),
    ];

    final sampleItems = [
      BackupDataPlaylistItem(id: 10, playlistId: 1, songId: 1, position: 0),
      BackupDataPlaylistItem(id: 11, playlistId: 1, songId: 2, position: 1),
    ];

    test('formatBackupJson serializes entities into valid versioned JSON', () {
      final jsonStr = BackupManager.formatBackupJson(
        songs: sampleSongs,
        playlists: samplePlaylists,
        playlistItems: sampleItems,
        exportedAt: now,
      );

      final decoded = json.decode(jsonStr) as Map<String, dynamic>;
      expect(decoded['schema_version'], equals(1));
      expect(decoded['exported_at'], equals(now.toIso8601String()));
      expect((decoded['songs'] as List).length, equals(2));
      expect((decoded['playlists'] as List).length, equals(1));
      expect((decoded['playlist_items'] as List).length, equals(2));
    });

    test(
      'round-trip serialization and deserialization produces identical data',
      () {
        final jsonStr = BackupManager.formatBackupJson(
          songs: sampleSongs,
          playlists: samplePlaylists,
          playlistItems: sampleItems,
          exportedAt: now,
        );

        final result = BackupManager.validateAndParse(jsonStr);
        expect(result.isValid, isTrue);
        expect(result.errorMessage, isNull);

        final payload = result.payload!;
        expect(payload.schemaVersion, equals(1));
        expect(payload.songs.length, equals(2));
        expect(payload.songs[0].title, equals('10,000 Reasons'));
        expect(
          payload.songs[0].url,
          equals(
            'https://tabs.ultimate-guitar.com/tab/matt-redman/10000-reasons-1',
          ),
        );
        expect(payload.songs[0].keyNote, equals('G'));
        expect(payload.songs[0].notes, equals('Capo 2'));
        expect(payload.songs[0].archived, isFalse);

        expect(payload.songs[1].title, equals('Oceans'));
        expect(payload.songs[1].notes, isNull);
        expect(payload.songs[1].archived, isTrue);

        expect(payload.playlists.length, equals(1));
        expect(payload.playlists[0].name, equals('Sunday Worship Nov 29'));
        expect(
          payload.playlists[0].serviceDate,
          equals(DateTime(2026, 11, 29)),
        );

        expect(payload.playlistItems.length, equals(2));
        expect(payload.playlistItems[0].playlistId, equals(1));
        expect(payload.playlistItems[0].songId, equals(1));
        expect(payload.playlistItems[0].position, equals(0));
        expect(payload.playlistItems[1].position, equals(1));
      },
    );

    test(
      'supports older or minimal schema with safe defaults for optional fields',
      () {
        final minimalJson = json.encode({
          'schema_version': 1,
          'songs': [
            {
              'id': 5,
              'title': 'Cornerstone',
              'url':
                  'https://tabs.ultimate-guitar.com/tab/hillsong/cornerstone-5',
            },
          ],
          'playlists': [
            {
              'id': 2,
              'name': 'Christmas Special',
              'service_date': '2026-12-25T00:00:00.000',
            },
          ],
          'playlist_items': [
            {'id': 1, 'playlist_id': 2, 'song_id': 5, 'position': 0},
          ],
        });

        final result = BackupManager.validateAndParse(minimalJson);
        expect(result.isValid, isTrue);
        final song = result.payload!.songs.first;
        expect(song.title, equals('Cornerstone'));
        expect(song.notes, isNull);
        expect(song.keyNote, isNull);
        expect(song.archived, isFalse);
      },
    );

    test('rejects malformed non-JSON string', () {
      final result = BackupManager.validateAndParse('Not a JSON string');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Invalid JSON syntax'));
    });

    test('rejects JSON that is not an object', () {
      final result = BackupManager.validateAndParse('[1, 2, 3]');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Root must be a JSON object'));
    });

    test('rejects unsupported future schema version', () {
      final jsonStr = json.encode({
        'schema_version': 2,
        'songs': [],
        'playlists': [],
        'playlist_items': [],
      });

      final result = BackupManager.validateAndParse(jsonStr);
      expect(result.isValid, isFalse);
      expect(
        result.errorMessage,
        contains('Unsupported backup schema version: 2'),
      );
    });

    test('rejects missing or zero schema version', () {
      final jsonStr = json.encode({'schema_version': 0, 'songs': []});

      final result = BackupManager.validateAndParse(jsonStr);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Invalid schema version'));
    });

    test('rejects song with invalid UG URL', () {
      final jsonStr = json.encode({
        'schema_version': 1,
        'songs': [
          {
            'id': 1,
            'title': 'Invalid URL Song',
            'url': 'https://google.com/search?q=chords',
          },
        ],
        'playlists': [],
        'playlist_items': [],
      });

      final result = BackupManager.validateAndParse(jsonStr);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Invalid Ultimate Guitar URL'));
    });

    test('rejects song with missing title', () {
      final jsonStr = json.encode({
        'schema_version': 1,
        'songs': [
          {
            'id': 1,
            'title': '',
            'url': 'https://tabs.ultimate-guitar.com/tab/s1',
          },
        ],
        'playlists': [],
        'playlist_items': [],
      });

      final result = BackupManager.validateAndParse(jsonStr);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Song title cannot be empty'));
    });

    test('rejects playlist item with negative position', () {
      final jsonStr = json.encode({
        'schema_version': 1,
        'songs': [
          {
            'id': 1,
            'title': 'Song 1',
            'url': 'https://tabs.ultimate-guitar.com/tab/s1',
          },
        ],
        'playlists': [
          {'id': 1, 'name': 'P1', 'service_date': '2026-11-29T00:00:00.000'},
        ],
        'playlist_items': [
          {'id': 1, 'playlist_id': 1, 'song_id': 1, 'position': -1},
        ],
      });

      final result = BackupManager.validateAndParse(jsonStr);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('negative position'));
    });

    test('needsWeeklyBackupNudge logic checks 7-day interval', () {
      final referenceDate = DateTime(2026, 11, 23);

      // Never backed up -> needs nudge
      expect(
        BackupManager.needsWeeklyBackupNudge(
          lastBackupAt: null,
          now: referenceDate,
        ),
        isTrue,
      );

      // Backed up 8 days ago -> needs nudge
      expect(
        BackupManager.needsWeeklyBackupNudge(
          lastBackupAt: referenceDate.subtract(const Duration(days: 8)),
          now: referenceDate,
        ),
        isTrue,
      );

      // Backed up 7 days ago -> needs nudge
      expect(
        BackupManager.needsWeeklyBackupNudge(
          lastBackupAt: referenceDate.subtract(const Duration(days: 7)),
          now: referenceDate,
        ),
        isTrue,
      );

      // Backed up 6 days ago -> does not need nudge
      expect(
        BackupManager.needsWeeklyBackupNudge(
          lastBackupAt: referenceDate.subtract(const Duration(days: 6)),
          now: referenceDate,
        ),
        isFalse,
      );

      // Backed up 1 hour ago -> does not need nudge
      expect(
        BackupManager.needsWeeklyBackupNudge(
          lastBackupAt: referenceDate.subtract(const Duration(hours: 1)),
          now: referenceDate,
        ),
        isFalse,
      );
    });
  });
}
