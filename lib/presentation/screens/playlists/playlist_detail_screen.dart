import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/domain/date_utils.dart';
import 'package:worship_setlist/presentation/providers/playlists_provider.dart';
import 'package:worship_setlist/presentation/providers/service_provider.dart';
import 'package:worship_setlist/presentation/screens/playlists/edit_playlist_dialog.dart';
import 'package:worship_setlist/presentation/screens/playlists/song_picker_dialog.dart';
import 'package:worship_setlist/presentation/screens/service/service_screen.dart';

/// Detailed view of a Sunday playlist (spec.md Section 5.2).
class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  late Playlist _currentPlaylist;

  @override
  void initState() {
    super.initState();
    _currentPlaylist = widget.playlist;
  }

  Future<void> _addSongs() async {
    final selectedIds = await showDialog<List<int>>(
      context: context,
      builder: (_) => const SongPickerDialog(),
    );

    if (selectedIds != null && selectedIds.isNotEmpty) {
      await ref
          .read(playlistsControllerProvider.notifier)
          .addSongsToPlaylist(
            playlistId: _currentPlaylist.id,
            songIds: selectedIds,
          );
    }
  }

  Future<void> _removeItem(int itemId, String title) async {
    await ref
        .read(playlistsControllerProvider.notifier)
        .removeItem(itemId: itemId);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Removed "$title" from playlist')));
    }
  }

  void _editPlaylist() async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => EditPlaylistDialog(playlist: _currentPlaylist),
    );

    if (updated == true) {
      // Re-fetch playlist
      final fresh = await ref
          .read(playlistsStreamProvider.future)
          .then((list) => list.firstWhere((p) => p.id == _currentPlaylist.id));
      setState(() => _currentPlaylist = fresh);
    }
  }

  Future<void> _startService(List<PlaylistItemWithSong> items) async {
    if (items.isEmpty) return;

    final storage = ref.read(servicePositionStorageProvider);
    final savedPosition = await storage.getSavedPosition(_currentPlaylist.id);

    int targetIndex = 0;

    if (savedPosition > 0 && savedPosition < items.length) {
      if (!mounted) return;
      final songTitle = items[savedPosition].song.title;
      final resumeChoice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const Key('resume_service_dialog'),
          title: const Text('Resume Service?'),
          content: Text(
            'Resume from song ${savedPosition + 1} ("$songTitle") or start from the beginning?',
          ),
          actions: [
            TextButton(
              key: const Key('resume_dialog_restart_button'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Start from Beginning'),
            ),
            FilledButton(
              key: const Key('resume_dialog_resume_button'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Resume'),
            ),
          ],
        ),
      );

      if (resumeChoice == null) {
        // User dismissed the dialog, cancel launching service mode
        return;
      }

      targetIndex = resumeChoice ? savedPosition : 0;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServiceScreen(
          playlistId: _currentPlaylist.id,
          items: items,
          initialIndex: targetIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(
      playlistItemsStreamProvider(_currentPlaylist.id),
    );
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentPlaylist.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit playlist name/date',
            onPressed: _editPlaylist,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ServiceDateUtils.formatServiceDate(
                        _currentPlaylist.serviceDate,
                      ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    itemsAsync.when(
                      data: (items) => Text(
                        '${items.length} ${items.length == 1 ? 'song' : 'songs'} in setlist',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      loading: () => const Text('Loading...'),
                      error: (e, s) => const SizedBox.shrink(),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  key: const Key('start_service_button'),
                  onPressed: itemsAsync.maybeWhen(
                    data: (items) =>
                        items.isNotEmpty ? () => _startService(items) : null,
                    orElse: () => null,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start Service'),
                ),
              ],
            ),
          ),
          Expanded(
            child: itemsAsync.when(
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.music_off_rounded,
                            size: 64,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Setlist is empty',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap "Add Songs" below to select worship songs from your library.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            key: const Key('add_songs_empty_button'),
                            onPressed: _addSongs,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Songs'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ReorderableListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 80),
                  itemCount: items.length,
                  onReorderItem: (oldIndex, newIndex) {
                    ref
                        .read(playlistsControllerProvider.notifier)
                        .reorderItems(
                          playlistId: _currentPlaylist.id,
                          oldIndex: oldIndex,
                          newIndex: newIndex,
                        );
                  },
                  itemBuilder: (context, index) {
                    final itemWithSong = items[index];
                    final item = itemWithSong.item;
                    final song = itemWithSong.song;

                    final hasKey =
                        song.keyNote != null && song.keyNote!.trim().isNotEmpty;
                    final hasNotes =
                        song.notes != null && song.notes!.trim().isNotEmpty;

                    return Card(
                      key: ValueKey(item.id),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${index + 1}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          song.title,
                                          style: theme.textTheme.bodyLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (hasKey)
                                        Container(
                                          margin: const EdgeInsets.only(
                                            left: 6,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme
                                                .primaryContainer,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            song.keyNote!,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: theme
                                                      .colorScheme
                                                      .onPrimaryContainer,
                                                ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (hasNotes) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      song.notes!,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              tooltip: 'Remove',
                              onPressed: () => _removeItem(item.id, song.title),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(
                                Icons.drag_handle_rounded,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) =>
                  Center(child: Text('Error loading setlist: $err')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'playlist_detail_fab',
        key: const Key('playlist_detail_add_songs_fab'),
        onPressed: _addSongs,
        icon: const Icon(Icons.playlist_add_rounded),
        label: const Text('Add Songs'),
      ),
    );
  }
}
