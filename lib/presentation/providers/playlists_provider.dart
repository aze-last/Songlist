import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/presentation/providers/database_provider.dart';

/// Stream of all playlists sorted by service date descending (newest first).
final playlistsStreamProvider = StreamProvider<List<Playlist>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchPlaylists();
});

/// Stream of playlist items with resolved song details, ordered by position ASC.
final playlistItemsStreamProvider =
    StreamProvider.family<List<PlaylistItemWithSong>, int>((ref, playlistId) {
      final db = ref.watch(databaseProvider);
      return db.watchPlaylistItemsWithSong(playlistId);
    });

/// Controller handling playlist operations (create, update, delete, duplicate, reorder, add/remove songs).
class PlaylistsController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  AppDatabase get _db => ref.read(databaseProvider);

  /// Creates a new playlist.
  Future<int> createPlaylist({
    required String name,
    required DateTime serviceDate,
  }) async {
    state = const AsyncValue.loading();
    try {
      final id = await _db.createPlaylist(
        name: name.trim(),
        serviceDate: serviceDate,
      );
      state = const AsyncValue.data(null);
      return id;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Updates playlist title and service date.
  Future<bool> updatePlaylist({
    required int id,
    required String name,
    required DateTime serviceDate,
  }) async {
    state = const AsyncValue.loading();
    try {
      final ok = await _db.updatePlaylist(
        id: id,
        name: name.trim(),
        serviceDate: serviceDate,
      );
      state = const AsyncValue.data(null);
      return ok;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Deletes a playlist. Cascade deletes playlist_items in SQLite.
  Future<int> deletePlaylist(int id) async {
    state = const AsyncValue.loading();
    try {
      final rows = await _db.deletePlaylist(id);
      state = const AsyncValue.data(null);
      return rows;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Duplicates a playlist ("Copy as new Sunday").
  Future<int> duplicatePlaylist({
    required int sourcePlaylistId,
    required String newName,
    required DateTime newServiceDate,
  }) async {
    state = const AsyncValue.loading();
    try {
      final newId = await _db.duplicatePlaylist(
        sourcePlaylistId: sourcePlaylistId,
        newName: newName.trim(),
        newServiceDate: newServiceDate,
      );
      state = const AsyncValue.data(null);
      return newId;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Adds multiple songs to a playlist with strictly contiguous positions.
  Future<void> addSongsToPlaylist({
    required int playlistId,
    required List<int> songIds,
  }) async {
    state = const AsyncValue.loading();
    try {
      for (final songId in songIds) {
        await _db.addSongToPlaylist(playlistId: playlistId, songId: songId);
      }
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Removes an item from a playlist and renormalizes positions.
  Future<void> removeItem({required int itemId}) async {
    state = const AsyncValue.loading();
    try {
      await _db.removePlaylistItem(itemId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Reorders items in a playlist atomically.
  Future<void> reorderItems({
    required int playlistId,
    required int oldIndex,
    required int newIndex,
  }) async {
    state = const AsyncValue.loading();
    try {
      final items = await _db.getPlaylistItemsWithSong(playlistId);
      final itemIds = items.map((i) => i.item.id).toList();

      if (oldIndex < 0 ||
          oldIndex >= itemIds.length ||
          newIndex < 0 ||
          newIndex > itemIds.length) {
        return;
      }

      var destination = newIndex;
      if (destination > oldIndex) {
        destination -= 1;
      }

      final moved = itemIds.removeAt(oldIndex);
      itemIds.insert(destination, moved);

      await _db.reorderPlaylistItems(playlistId, itemIds);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

/// Provider for the PlaylistsController.
final playlistsControllerProvider =
    NotifierProvider<PlaylistsController, AsyncValue<void>>(
      PlaylistsController.new,
    );
