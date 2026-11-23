import 'package:drift/drift.dart';

/// Songs table: stores song links to Ultimate Guitar and user notes.
///
/// Under spec.md Section 1, this table stores ONLY the user's title, URL,
/// short notes, and key note. NO chords or lyrics are ever stored.
/// Songs are archived, never hard-deleted.
class Songs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1)();
  TextColumn get url => text().withLength(min: 1)();
  TextColumn get notes => text().nullable()();
  TextColumn get keyNote => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

/// Playlists table: weekly playlists organized by Sunday service date.
@TableIndex(name: 'idx_playlists_service_date', columns: {#serviceDate})
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1)();
  DateTimeColumn get serviceDate => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Playlist items table: connects songs to playlists with a contiguous position.
///
/// Contiguous 0..n-1 positions per playlist.
/// Deleting a playlist cascades to its playlist items.
@TableIndex(
  name: 'idx_playlist_items_playlist_position',
  columns: {#playlistId, #position},
)
class PlaylistItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get playlistId =>
      integer().references(Playlists, #id, onDelete: KeyAction.cascade)();
  IntColumn get songId => integer().references(Songs, #id)();
  IntColumn get position => integer()();
}

/// App settings table: records update check timestamps and backup reminders.
class AppSettings extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get lastUpdateCheck => dateTime().nullable()();
  TextColumn get skippedVersion => text().nullable()();
  DateTimeColumn get lastBackupAt => dateTime().nullable()();
}
