import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/domain/url_validator.dart';
import 'package:worship_setlist/presentation/providers/database_provider.dart';

/// Stream of all active (non-archived) songs from SQLite.
final activeSongsStreamProvider = StreamProvider<List<Song>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchActiveSongs();
});

/// Search query notifier for songs library.
class SongSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }
}

/// Provider for the search query.
final songSearchQueryProvider =
    NotifierProvider<SongSearchQueryNotifier, String>(
      SongSearchQueryNotifier.new,
    );

/// Filtered list of songs matching the current search query.
final filteredSongsProvider = Provider<AsyncValue<List<Song>>>((ref) {
  final songsAsync = ref.watch(activeSongsStreamProvider);
  final query = ref.watch(songSearchQueryProvider).trim().toLowerCase();

  return songsAsync.whenData((songs) {
    if (query.isEmpty) return songs;
    return songs.where((s) {
      final titleMatch = s.title.toLowerCase().contains(query);
      final notesMatch = s.notes?.toLowerCase().contains(query) ?? false;
      final keyMatch = s.keyNote?.toLowerCase().contains(query) ?? false;
      return titleMatch || notesMatch || keyMatch;
    }).toList();
  });
});

/// Controller handling song mutations (add, edit, archive, restore).
class SongsController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  AppDatabase get _db => ref.read(databaseProvider);

  /// Adds a new song with strict URL validation and duplicate detection.
  ///
  /// Returns null on success, or a human-readable error message on failure.
  Future<String?> addSong({
    required String rawUrl,
    required String title,
    String? notes,
    String? keyNote,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      return 'Song title cannot be empty.';
    }

    final validation = UrlValidator.validateAndNormalize(rawUrl);
    if (!validation.isValid) {
      return validation.errorMessage ?? 'Invalid Ultimate Guitar URL.';
    }

    final normalizedUrl = validation.normalizedUrl!;

    // Check for duplicate normalized URL in the database
    final existing = await _db.findSongByUrl(normalizedUrl);
    if (existing != null) {
      return 'This tab already exists as "${existing.title}".';
    }

    state = const AsyncValue.loading();
    try {
      await _db.insertSong(
        title: trimmedTitle,
        url: normalizedUrl,
        notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
        keyNote: keyNote?.trim().isEmpty == true ? null : keyNote?.trim(),
      );
      state = const AsyncValue.data(null);
      return null;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return 'Failed to save song: $e';
    }
  }

  /// Updates an existing song.
  Future<String?> updateSong({
    required int id,
    required String title,
    required String rawUrl,
    String? notes,
    String? keyNote,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      return 'Song title cannot be empty.';
    }

    final validation = UrlValidator.validateAndNormalize(rawUrl);
    if (!validation.isValid) {
      return validation.errorMessage ?? 'Invalid Ultimate Guitar URL.';
    }

    final normalizedUrl = validation.normalizedUrl!;

    // Check if another song already has this normalized URL
    final existing = await _db.findSongByUrl(normalizedUrl);
    if (existing != null && existing.id != id) {
      return 'Another song already uses this URL ("${existing.title}").';
    }

    state = const AsyncValue.loading();
    try {
      await _db.updateSongDetails(
        id: id,
        title: trimmedTitle,
        url: normalizedUrl,
        notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
        keyNote: keyNote?.trim().isEmpty == true ? null : keyNote?.trim(),
      );
      state = const AsyncValue.data(null);
      return null;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return 'Failed to update song: $e';
    }
  }

  /// Archives a song (soft delete, preserving playlists).
  Future<bool> archiveSong(int id) async {
    state = const AsyncValue.loading();
    try {
      final ok = await _db.archiveSong(id);
      state = const AsyncValue.data(null);
      return ok;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Restores an archived song.
  Future<bool> restoreSong(int id) async {
    state = const AsyncValue.loading();
    try {
      final ok = await _db.restoreSong(id);
      state = const AsyncValue.data(null);
      return ok;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

/// Provider for the SongsController.
final songsControllerProvider =
    NotifierProvider<SongsController, AsyncValue<void>>(SongsController.new);
