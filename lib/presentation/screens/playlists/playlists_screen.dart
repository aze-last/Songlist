import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_setlist/presentation/providers/playlists_provider.dart';
import 'package:worship_setlist/presentation/screens/playlists/create_playlist_dialog.dart';
import 'package:worship_setlist/presentation/screens/playlists/playlist_card.dart';
import 'package:worship_setlist/presentation/widgets/weekly_backup_banner.dart';

/// Primary Playlists screen listing Sunday services (spec.md Section 5.2).
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  void _showCreatePlaylist(BuildContext context) {
    showDialog(context: context, builder: (_) => const CreatePlaylistDialog());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsStreamProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Playlists'), centerTitle: false),
      body: Column(
        children: [
          const WeeklyBackupBanner(),
          Expanded(
            child: playlistsAsync.when(
              data: (playlists) {
                if (playlists.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.queue_music_rounded,
                            size: 64,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No playlists yet',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Create a playlist for your upcoming Sunday worship service.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            key: const Key('create_first_playlist_button'),
                            onPressed: () => _showCreatePlaylist(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Create Playlist'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 80),
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return PlaylistCard(
                      key: ValueKey(playlist.id),
                      playlist: playlist,
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) =>
                  Center(child: Text('Error loading playlists: $err')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'playlists_fab',
        key: const Key('playlists_fab_add'),
        onPressed: () => _showCreatePlaylist(context),
        icon: const Icon(Icons.add),
        label: const Text('New Playlist'),
      ),
    );
  }
}
