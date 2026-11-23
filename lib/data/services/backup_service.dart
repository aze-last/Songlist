import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/domain/backup_manager.dart';
import 'package:worship_setlist/presentation/providers/database_provider.dart';

/// Service managing full backup JSON export and import (spec.md Section 6).
class BackupService {
  final AppDatabase _db;
  final Future<Directory> Function()? tempDirProvider;

  BackupService(this._db, {this.tempDirProvider});

  /// Generates the complete backup JSON string from SQLite data.
  Future<String> generateBackupJson({DateTime? exportedAt}) async {
    final songs = await _db.getAllSongs();
    final playlists = await _db.getAllPlaylists();
    final items = await _db.getAllPlaylistItems();

    final backupSongs = songs
        .map(
          (s) => BackupDataSong(
            id: s.id,
            title: s.title,
            url: s.url,
            notes: s.notes,
            keyNote: s.keyNote,
            createdAt: s.createdAt,
            archived: s.archived,
          ),
        )
        .toList();

    final backupPlaylists = playlists
        .map(
          (p) => BackupDataPlaylist(
            id: p.id,
            name: p.name,
            serviceDate: p.serviceDate,
            createdAt: p.createdAt,
          ),
        )
        .toList();

    final backupItems = items
        .map(
          (i) => BackupDataPlaylistItem(
            id: i.id,
            playlistId: i.playlistId,
            songId: i.songId,
            position: i.position,
          ),
        )
        .toList();

    return BackupManager.formatBackupJson(
      songs: backupSongs,
      playlists: backupPlaylists,
      playlistItems: backupItems,
      exportedAt: exportedAt,
    );
  }

  /// Writes backup JSON to a temporary file and records backup timestamp.
  Future<String> exportBackupToFile() async {
    final jsonStr = await generateBackupJson();
    final tempDir = tempDirProvider != null
        ? await tempDirProvider!()
        : await getTemporaryDirectory();
    final filename =
        'worship_setlist_backup_${DateTime.now().millisecondsSinceEpoch}.json';
    final filePath = p.join(tempDir.path, filename);

    final file = File(filePath);
    file.writeAsStringSync(jsonStr, flush: true);

    await _db.updateSettings(lastBackupAt: DateTime.now());
    return filePath;
  }

  /// Exports backup and invokes the system share sheet.
  Future<void> shareBackup() async {
    final filePath = await exportBackupToFile();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath, mimeType: 'application/json')],
        subject: 'Worship Setlist Backup',
      ),
    );
  }

  /// Validates a backup file from disk.
  Future<BackupValidationResult> validateFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      return const BackupValidationResult.failure('Backup file not found.');
    }
    final content = file.readAsStringSync();
    return BackupManager.validateAndParse(content);
  }

  /// Restores all database tables from a validated payload.
  Future<void> restoreFromPayload(BackupPayload payload) async {
    final songCompanions = payload.songs
        .map(
          (s) => SongsCompanion.insert(
            id: Value(s.id),
            title: s.title,
            url: s.url,
            notes: Value(s.notes),
            keyNote: Value(s.keyNote),
            createdAt: Value(s.createdAt),
            archived: Value(s.archived),
          ),
        )
        .toList();

    final playlistCompanions = payload.playlists
        .map(
          (p) => PlaylistsCompanion.insert(
            id: Value(p.id),
            name: p.name,
            serviceDate: p.serviceDate,
            createdAt: Value(p.createdAt),
          ),
        )
        .toList();

    final itemCompanions = payload.playlistItems
        .map(
          (i) => PlaylistItemsCompanion.insert(
            id: Value(i.id),
            playlistId: i.playlistId,
            songId: i.songId,
            position: i.position,
          ),
        )
        .toList();

    await _db.restoreAllData(
      songCompanions: songCompanions,
      playlistCompanions: playlistCompanions,
      itemCompanions: itemCompanions,
    );
  }
}

final backupServiceProvider = Provider<BackupService>((ref) {
  final db = ref.watch(databaseProvider);
  return BackupService(db);
});

final lastBackupTimeStreamProvider = StreamProvider<DateTime?>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.appSettings)..where((s) => s.id.equals(1)))
      .watchSingleOrNull()
      .map((s) => s?.lastBackupAt);
});
