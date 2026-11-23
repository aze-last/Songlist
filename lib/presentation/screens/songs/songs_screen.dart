import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/presentation/providers/songs_provider.dart';
import 'package:worship_setlist/presentation/screens/songs/browse_ug_screen.dart';
import 'package:worship_setlist/presentation/screens/songs/edit_song_dialog.dart';
import 'package:worship_setlist/presentation/screens/songs/paste_link_dialog.dart';
import 'package:worship_setlist/presentation/screens/songs/song_card.dart';

/// Primary Songs Library screen (spec.md Section 5.1).
class SongsScreen extends ConsumerStatefulWidget {
  const SongsScreen({super.key});

  @override
  ConsumerState<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends ConsumerState<SongsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddSongOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.travel_explore_rounded),
                title: const Text('Browse Ultimate Guitar'),
                subtitle: const Text(
                  'Search UG in-app and tap "Save this song"',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BrowseUgScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.link_rounded),
                title: const Text('Paste Link'),
                subtitle: const Text('Paste a tab URL directly'),
                onTap: () {
                  Navigator.pop(ctx);
                  showDialog(
                    context: context,
                    builder: (_) => const PasteLinkDialog(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmArchiveSong(BuildContext context, Song song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Song?'),
        content: Text(
          'Archive "${song.title}"?\n\nIt will be hidden from your library, but existing playlists will remain intact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref
          .read(songsControllerProvider.notifier)
          .archiveSong(song.id);

      if (context.mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Archived "${song.title}"'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                ref.read(songsControllerProvider.notifier).restoreSong(song.id);
              },
            ),
          ),
        );
      }
    }
  }

  void _showEditSong(BuildContext context, Song song) {
    showDialog(
      context: context,
      builder: (_) => EditSongDialog(song: song),
    );
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(filteredSongsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Song Library'), centerTitle: false),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search songs by title, note, or key...',
              leading: const Icon(Icons.search),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      ref.read(songSearchQueryProvider.notifier).setQuery('');
                      setState(() {});
                    },
                  ),
              ],
              onChanged: (val) {
                ref.read(songSearchQueryProvider.notifier).setQuery(val);
                setState(() {});
              },
            ),
          ),
          Expanded(
            child: songsAsync.when(
              data: (songs) {
                if (songs.isEmpty) {
                  final isSearching = _searchController.text.trim().isNotEmpty;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isSearching
                                ? Icons.search_off_rounded
                                : Icons.music_note_rounded,
                            size: 64,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isSearching
                                ? 'No songs match "${_searchController.text.trim()}".'
                                : 'Your song library is empty.',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isSearching
                                ? 'Try a different search query or clear the filter.'
                                : 'Add songs by browsing Ultimate Guitar or pasting a tab link.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (!isSearching) ...[
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: () => _showAddSongOptions(context),
                              icon: const Icon(Icons.add),
                              label: const Text('Add First Song'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: songs.length,
                  padding: const EdgeInsets.only(bottom: 80, top: 4),
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return SongCard(
                      key: ValueKey(song.id),
                      song: song,
                      onEdit: () => _showEditSong(context, song),
                      onArchive: () => _confirmArchiveSong(context, song),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) =>
                  Center(child: Text('Error loading songs: $err')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'songs_fab',
        onPressed: () => _showAddSongOptions(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Song'),
      ),
    );
  }
}
