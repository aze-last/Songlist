import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:worship_setlist/data/database/tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Songs, Playlists, PlaylistItems, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // Mandatory SQLite foreign keys activation
      await customStatement('PRAGMA foreign_keys = ON;');
    },
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'worship_setlist');
  }

  // =========================================================================
  // SONG OPERATIONS (spec.md Sections 4 & 5.1)
  // Songs are archived, never hard-deleted.
  // =========================================================================

  /// Insert a new song.
  Future<int> insertSong({
    required String title,
    required String url,
    String? notes,
    String? keyNote,
  }) {
    return into(songs).insert(
      SongsCompanion.insert(
        title: title,
        url: url,
        notes: Value(notes),
        keyNote: Value(keyNote),
      ),
    );
  }

  /// Watch all active (unarchived) songs, sorted by title.
  Stream<List<Song>> watchActiveSongs() {
    return (select(songs)
          ..where((s) => s.archived.equals(false))
          ..orderBy([(s) => OrderingTerm.asc(s.title)]))
        .watch();
  }

  /// Get all active songs as a future.
  Future<List<Song>> getActiveSongs() {
    return (select(songs)
          ..where((s) => s.archived.equals(false))
          ..orderBy([(s) => OrderingTerm.asc(s.title)]))
        .get();
  }

  /// Get a song by its primary key ID.
  Future<Song?> getSongById(int id) {
    return (select(songs)..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  /// Find active or archived song by normalized URL.
  Future<Song?> findSongByUrl(String url) {
    return (select(songs)..where((s) => s.url.equals(url))).getSingleOrNull();
  }

  /// Update song details (title, url, notes, keyNote).
  Future<bool> updateSongDetails({
    required int id,
    required String title,
    required String url,
    String? notes,
    String? keyNote,
  }) async {
    final count = await (update(songs)..where((s) => s.id.equals(id))).write(
      SongsCompanion(
        title: Value(title),
        url: Value(url),
        notes: Value(notes),
        keyNote: Value(keyNote),
      ),
    );
    return count > 0;
  }

  /// Archive a song (soft-delete). Keeps historical playlists intact.
  Future<bool> archiveSong(int id) async {
    final count = await (update(songs)..where((s) => s.id.equals(id))).write(
      const SongsCompanion(archived: Value(true)),
    );
    return count > 0;
  }

  /// Restore an archived song.
  Future<bool> restoreSong(int id) async {
    final count = await (update(songs)..where((s) => s.id.equals(id))).write(
      const SongsCompanion(archived: Value(false)),
    );
    return count > 0;
  }

  // =========================================================================
  // PLAYLIST OPERATIONS (spec.md Sections 4 & 5.2)
  // =========================================================================

  /// Create a new playlist.
  Future<int> createPlaylist({
    required String name,
    required DateTime serviceDate,
  }) {
    return into(
      playlists,
    ).insert(PlaylistsCompanion.insert(name: name, serviceDate: serviceDate));
  }

  /// Watch playlists sorted by service date descending (newest first).
  Stream<List<Playlist>> watchPlaylists() {
    return (select(
      playlists,
    )..orderBy([(p) => OrderingTerm.desc(p.serviceDate)])).watch();
  }

  /// Get playlists sorted by service date descending.
  Future<List<Playlist>> getPlaylists() {
    return (select(
      playlists,
    )..orderBy([(p) => OrderingTerm.desc(p.serviceDate)])).get();
  }

  /// Get playlist by ID.
  Future<Playlist?> getPlaylistById(int id) {
    return (select(playlists)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  /// Update playlist name and service date.
  Future<bool> updatePlaylist({
    required int id,
    required String name,
    required DateTime serviceDate,
  }) async {
    final count = await (update(playlists)..where((p) => p.id.equals(id)))
        .write(
          PlaylistsCompanion(
            name: Value(name),
            serviceDate: Value(serviceDate),
          ),
        );
    return count > 0;
  }

  /// Delete a playlist.
  /// SQLite foreign keys cascade automatically removes playlist items,
  /// but we wrap in a transaction for explicit safety.
  Future<int> deletePlaylist(int id) {
    return transaction(() async {
      await (delete(
        playlistItems,
      )..where((item) => item.playlistId.equals(id))).go();
      return (delete(playlists)..where((p) => p.id.equals(id))).go();
    });
  }

  /// Duplicate a playlist (e.g. "Copy as new Sunday").
  Future<int> duplicatePlaylist({
    required int sourcePlaylistId,
    required String newName,
    required DateTime newServiceDate,
  }) {
    return transaction(() async {
      final newPlaylistId = await createPlaylist(
        name: newName,
        serviceDate: newServiceDate,
      );

      final currentItems =
          await (select(playlistItems)
                ..where((i) => i.playlistId.equals(sourcePlaylistId))
                ..orderBy([(i) => OrderingTerm.asc(i.position)]))
              .get();

      for (var i = 0; i < currentItems.length; i++) {
        await into(playlistItems).insert(
          PlaylistItemsCompanion.insert(
            playlistId: newPlaylistId,
            songId: currentItems[i].songId,
            position: i,
          ),
        );
      }

      return newPlaylistId;
    });
  }

  // =========================================================================
  // PLAYLIST ITEMS OPERATIONS (spec.md Sections 4 & 5.2)
  // Ensures contiguous 0..n-1 positions per playlist.
  // =========================================================================

  /// Watch items in a playlist with resolved song data, ordered by position ASC.
  Stream<List<PlaylistItemWithSong>> watchPlaylistItemsWithSong(
    int playlistId,
  ) {
    final query =
        select(playlistItems)
            .join([innerJoin(songs, songs.id.equalsExp(playlistItems.songId))])
          ..where(playlistItems.playlistId.equals(playlistId))
          ..orderBy([OrderingTerm.asc(playlistItems.position)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        return PlaylistItemWithSong(
          item: row.readTable(playlistItems),
          song: row.readTable(songs),
        );
      }).toList();
    });
  }

  /// Get playlist items with resolved song data.
  Future<List<PlaylistItemWithSong>> getPlaylistItemsWithSong(
    int playlistId,
  ) async {
    final query =
        select(playlistItems)
            .join([innerJoin(songs, songs.id.equalsExp(playlistItems.songId))])
          ..where(playlistItems.playlistId.equals(playlistId))
          ..orderBy([OrderingTerm.asc(playlistItems.position)]);

    final rows = await query.get();
    return rows.map((row) {
      return PlaylistItemWithSong(
        item: row.readTable(playlistItems),
        song: row.readTable(songs),
      );
    }).toList();
  }

  /// Add a song to a playlist.
  /// Inserts at the end and guarantees contiguous position.
  Future<int> addSongToPlaylist({
    required int playlistId,
    required int songId,
  }) {
    return transaction(() async {
      final existingItems =
          await (select(playlistItems)
                ..where((i) => i.playlistId.equals(playlistId))
                ..orderBy([(i) => OrderingTerm.asc(i.position)]))
              .get();

      final nextPos = existingItems.length;

      return into(playlistItems).insert(
        PlaylistItemsCompanion.insert(
          playlistId: playlistId,
          songId: songId,
          position: nextPos,
        ),
      );
    });
  }

  /// Remove an item and renormalize remaining items in that playlist to 0..n-1.
  Future<void> removePlaylistItem(int itemId) {
    return transaction(() async {
      final itemToRemove = await (select(
        playlistItems,
      )..where((i) => i.id.equals(itemId))).getSingleOrNull();

      if (itemToRemove == null) return;

      final playlistId = itemToRemove.playlistId;

      await (delete(playlistItems)..where((i) => i.id.equals(itemId))).go();

      // Renormalize positions of remaining items
      final remaining =
          await (select(playlistItems)
                ..where((i) => i.playlistId.equals(playlistId))
                ..orderBy([(i) => OrderingTerm.asc(i.position)]))
              .get();

      for (var i = 0; i < remaining.length; i++) {
        if (remaining[i].position != i) {
          await (update(playlistItems)
                ..where((item) => item.id.equals(remaining[i].id)))
              .write(PlaylistItemsCompanion(position: Value(i)));
        }
      }
    });
  }

  /// Atomically reorder items within a playlist using the provided ordered item IDs.
  Future<void> reorderPlaylistItems(int playlistId, List<int> orderedItemIds) {
    return transaction(() async {
      for (var i = 0; i < orderedItemIds.length; i++) {
        await (update(playlistItems)..where(
              (item) =>
                  item.id.equals(orderedItemIds[i]) &
                  item.playlistId.equals(playlistId),
            ))
            .write(PlaylistItemsCompanion(position: Value(i)));
      }
    });
  }

  // =========================================================================
  // APP SETTINGS OPERATIONS (spec.md Section 4 & 5.4)
  // =========================================================================

  /// Returns the current app settings, initializing row 1 if absent.
  Future<AppSetting> getOrCreateSettings() {
    return transaction(() async {
      final existing = await (select(
        appSettings,
      )..where((s) => s.id.equals(1))).getSingleOrNull();
      if (existing != null) return existing;

      await into(appSettings)
          .insert(AppSettingsCompanion.insert(id: const Value(1)));
      return (select(appSettings)..where((s) => s.id.equals(1))).getSingle();
    });
  }

  /// Updates settings fields.
  Future<void> updateSettings({
    DateTime? lastUpdateCheck,
    String? skippedVersion,
    DateTime? lastBackupAt,
  }) async {
    await getOrCreateSettings();
    await (update(appSettings)..where((s) => s.id.equals(1))).write(
      AppSettingsCompanion(
        lastUpdateCheck: lastUpdateCheck != null
            ? Value(lastUpdateCheck)
            : const Value.absent(),
        skippedVersion: skippedVersion != null
            ? Value(skippedVersion)
            : const Value.absent(),
        lastBackupAt: lastBackupAt != null
            ? Value(lastBackupAt)
            : const Value.absent(),
      ),
    );
  }

  // =========================================================================
  // BACKUP & RESTORE OPERATIONS (spec.md Section 6)
  // =========================================================================

  /// Get all songs (both active and archived) for backup export.
  Future<List<Song>> getAllSongs() {
    return (select(songs)..orderBy([(s) => OrderingTerm.asc(s.id)])).get();
  }

  /// Get all playlists for backup export.
  Future<List<Playlist>> getAllPlaylists() {
    return (select(playlists)..orderBy([(p) => OrderingTerm.asc(p.id)])).get();
  }

  /// Get all playlist items for backup export.
  Future<List<PlaylistItem>> getAllPlaylistItems() {
    return (select(playlistItems)..orderBy([
          (i) => OrderingTerm.asc(i.playlistId),
          (i) => OrderingTerm.asc(i.position),
        ]))
        .get();
  }

  /// Atomically restores all database tables from backup companions.
  Future<void> restoreAllData({
    required List<SongsCompanion> songCompanions,
    required List<PlaylistsCompanion> playlistCompanions,
    required List<PlaylistItemsCompanion> itemCompanions,
  }) {
    return transaction(() async {
      // Deletions child -> parent to respect foreign key constraints
      await delete(playlistItems).go();
      await delete(playlists).go();
      await delete(songs).go();

      // Insertions parent -> child
      for (final s in songCompanions) {
        await into(songs).insert(s);
      }
      for (final p in playlistCompanions) {
        await into(playlists).insert(p);
      }
      for (final item in itemCompanions) {
        await into(playlistItems).insert(item);
      }

      await updateSettings(lastBackupAt: DateTime.now());
    });
  }
}

/// Helper composite class representing a playlist item joined with its song.
class PlaylistItemWithSong {
  final PlaylistItem item;
  final Song song;

  const PlaylistItemWithSong({required this.item, required this.song});
}
