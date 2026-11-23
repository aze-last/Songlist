import 'dart:convert';

import 'package:worship_setlist/domain/url_validator.dart';

/// Current supported backup schema version (spec.md Section 6).
const int kCurrentBackupSchemaVersion = 1;

/// Domain representation of a song in a backup payload.
class BackupDataSong {
  final int id;
  final String title;
  final String url;
  final String? notes;
  final String? keyNote;
  final DateTime createdAt;
  final bool archived;

  const BackupDataSong({
    required this.id,
    required this.title,
    required this.url,
    this.notes,
    this.keyNote,
    required this.createdAt,
    this.archived = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'notes': notes,
    'key_note': keyNote,
    'created_at': createdAt.toIso8601String(),
    'archived': archived,
  };

  factory BackupDataSong.fromJson(Map<String, dynamic> json) {
    return BackupDataSong(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      notes: json['notes'] as String?,
      keyNote: json['key_note'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      archived: json['archived'] as bool? ?? false,
    );
  }
}

/// Domain representation of a playlist in a backup payload.
class BackupDataPlaylist {
  final int id;
  final String name;
  final DateTime serviceDate;
  final DateTime createdAt;

  const BackupDataPlaylist({
    required this.id,
    required this.name,
    required this.serviceDate,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'service_date': serviceDate.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  factory BackupDataPlaylist.fromJson(Map<String, dynamic> json) {
    return BackupDataPlaylist(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      serviceDate: json['service_date'] != null
          ? DateTime.tryParse(json['service_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Domain representation of a playlist item in a backup payload.
class BackupDataPlaylistItem {
  final int id;
  final int playlistId;
  final int songId;
  final int position;

  const BackupDataPlaylistItem({
    required this.id,
    required this.playlistId,
    required this.songId,
    required this.position,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'playlist_id': playlistId,
    'song_id': songId,
    'position': position,
  };

  factory BackupDataPlaylistItem.fromJson(Map<String, dynamic> json) {
    return BackupDataPlaylistItem(
      id: json['id'] as int? ?? 0,
      playlistId: json['playlist_id'] as int? ?? 0,
      songId: json['song_id'] as int? ?? 0,
      position: json['position'] as int? ?? 0,
    );
  }
}

/// Strongly-typed container holding a complete valid backup payload.
class BackupPayload {
  final int schemaVersion;
  final DateTime exportedAt;
  final List<BackupDataSong> songs;
  final List<BackupDataPlaylist> playlists;
  final List<BackupDataPlaylistItem> playlistItems;

  const BackupPayload({
    required this.schemaVersion,
    required this.exportedAt,
    required this.songs,
    required this.playlists,
    required this.playlistItems,
  });
}

/// Result of validating and parsing a backup JSON string.
class BackupValidationResult {
  final bool isValid;
  final String? errorMessage;
  final BackupPayload? payload;

  const BackupValidationResult.success(this.payload)
    : isValid = true,
      errorMessage = null;

  const BackupValidationResult.failure(this.errorMessage)
    : isValid = false,
      payload = null;
}

/// Pure Dart manager for backup formatting, validation, and parsing (spec.md Section 6).
class BackupManager {
  /// Format database entities into a versioned JSON backup string.
  static String formatBackupJson({
    required List<BackupDataSong> songs,
    required List<BackupDataPlaylist> playlists,
    required List<BackupDataPlaylistItem> playlistItems,
    DateTime? exportedAt,
  }) {
    final exportTime = exportedAt ?? DateTime.now();

    final map = {
      'schema_version': kCurrentBackupSchemaVersion,
      'exported_at': exportTime.toIso8601String(),
      'songs': songs.map((s) => s.toJson()).toList(),
      'playlists': playlists.map((p) => p.toJson()).toList(),
      'playlist_items': playlistItems.map((item) => item.toJson()).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Validates backup JSON and parses it into strongly-typed structures.
  static BackupValidationResult validateAndParse(String jsonString) {
    if (jsonString.trim().isEmpty) {
      return const BackupValidationResult.failure('Backup content is empty.');
    }

    dynamic decoded;
    try {
      decoded = json.decode(jsonString);
    } catch (e) {
      return BackupValidationResult.failure('Invalid JSON syntax: $e');
    }

    if (decoded is! Map<String, dynamic>) {
      return const BackupValidationResult.failure(
        'Root must be a JSON object with schema_version.',
      );
    }

    final schemaVersion = decoded['schema_version'];
    if (schemaVersion is! int || schemaVersion < 1) {
      return const BackupValidationResult.failure(
        'Invalid schema version. Expected positive integer.',
      );
    }

    if (schemaVersion > kCurrentBackupSchemaVersion) {
      return BackupValidationResult.failure(
        'Unsupported backup schema version: $schemaVersion. '
        'This backup was created by a newer version of Worship Setlist.',
      );
    }

    // Exported At
    DateTime exportedAt = DateTime.now();
    if (decoded['exported_at'] != null) {
      final parsed = DateTime.tryParse(decoded['exported_at'] as String);
      if (parsed != null) exportedAt = parsed;
    }

    // Parse & Validate Songs
    final songsRaw = decoded['songs'];
    if (songsRaw != null && songsRaw is! List) {
      return const BackupValidationResult.failure(
        'Field "songs" must be a list.',
      );
    }

    final List<BackupDataSong> parsedSongs = [];
    if (songsRaw is List) {
      for (var i = 0; i < songsRaw.length; i++) {
        final item = songsRaw[i];
        if (item is! Map<String, dynamic>) {
          return BackupValidationResult.failure(
            'Song at index $i is not an object.',
          );
        }

        final title = item['title'];
        if (title is! String || title.trim().isEmpty) {
          return BackupValidationResult.failure(
            'Song title cannot be empty (index $i).',
          );
        }

        final url = item['url'];
        if (url is! String || url.trim().isEmpty) {
          return BackupValidationResult.failure(
            'Song URL cannot be empty (index $i).',
          );
        }

        final urlValidation = UrlValidator.validateAndNormalize(url);
        if (!urlValidation.isValid) {
          return BackupValidationResult.failure(
            'Invalid Ultimate Guitar URL for song "$title": ${urlValidation.errorMessage}',
          );
        }

        parsedSongs.add(BackupDataSong.fromJson(item));
      }
    }

    // Parse & Validate Playlists
    final playlistsRaw = decoded['playlists'];
    if (playlistsRaw != null && playlistsRaw is! List) {
      return const BackupValidationResult.failure(
        'Field "playlists" must be a list.',
      );
    }

    final List<BackupDataPlaylist> parsedPlaylists = [];
    if (playlistsRaw is List) {
      for (var i = 0; i < playlistsRaw.length; i++) {
        final item = playlistsRaw[i];
        if (item is! Map<String, dynamic>) {
          return BackupValidationResult.failure(
            'Playlist at index $i is not an object.',
          );
        }

        final name = item['name'];
        if (name is! String || name.trim().isEmpty) {
          return BackupValidationResult.failure(
            'Playlist name cannot be empty (index $i).',
          );
        }

        parsedPlaylists.add(BackupDataPlaylist.fromJson(item));
      }
    }

    // Parse & Validate Playlist Items
    final itemsRaw = decoded['playlist_items'];
    if (itemsRaw != null && itemsRaw is! List) {
      return const BackupValidationResult.failure(
        'Field "playlist_items" must be a list.',
      );
    }

    final List<BackupDataPlaylistItem> parsedItems = [];
    if (itemsRaw is List) {
      for (var i = 0; i < itemsRaw.length; i++) {
        final item = itemsRaw[i];
        if (item is! Map<String, dynamic>) {
          return BackupValidationResult.failure(
            'Playlist item at index $i is not an object.',
          );
        }

        final position = item['position'];
        if (position is! int || position < 0) {
          return BackupValidationResult.failure(
            'Playlist item at index $i has invalid/negative position: $position.',
          );
        }

        parsedItems.add(BackupDataPlaylistItem.fromJson(item));
      }
    }

    return BackupValidationResult.success(
      BackupPayload(
        schemaVersion: schemaVersion,
        exportedAt: exportedAt,
        songs: parsedSongs,
        playlists: parsedPlaylists,
        playlistItems: parsedItems,
      ),
    );
  }

  /// Calculates whether the user should be nudged with a weekly backup reminder (spec.md Section 6).
  static bool needsWeeklyBackupNudge({
    required DateTime? lastBackupAt,
    DateTime? now,
  }) {
    if (lastBackupAt == null) return true;
    final currentTime = now ?? DateTime.now();
    return currentTime.difference(lastBackupAt).inDays >= 7;
  }
}
