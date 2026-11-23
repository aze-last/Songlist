import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_setlist/presentation/providers/songs_provider.dart';

/// Modal dialog providing a searchable multi-select picker for library songs.
class SongPickerDialog extends ConsumerStatefulWidget {
  const SongPickerDialog({super.key});

  @override
  ConsumerState<SongPickerDialog> createState() => _SongPickerDialogState();
}

class _SongPickerDialogState extends ConsumerState<SongPickerDialog> {
  final _searchController = TextEditingController();
  final Set<int> _selectedSongIds = <int>{};
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeSongsAsync = ref.watch(activeSongsStreamProvider);
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Add Songs to Playlist'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search songs...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
              onChanged: (val) =>
                  setState(() => _query = val.trim().toLowerCase()),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: activeSongsAsync.when(
                data: (allSongs) {
                  final filtered = allSongs.where((s) {
                    if (_query.isEmpty) return true;
                    final title = s.title.toLowerCase();
                    final notes = s.notes?.toLowerCase() ?? '';
                    final key = s.keyNote?.toLowerCase() ?? '';
                    return title.contains(_query) ||
                        notes.contains(_query) ||
                        key.contains(_query);
                  }).toList();

                  if (filtered.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        _query.isEmpty
                            ? 'No songs in library yet. Add songs to your library first.'
                            : 'No songs matching "$_query".',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final song = filtered[index];
                      final isSelected = _selectedSongIds.contains(song.id);

                      return CheckboxListTile(
                        value: isSelected,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          song.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: (song.keyNote != null || song.notes != null)
                            ? Text(
                                [
                                  if (song.keyNote != null)
                                    'Key: ${song.keyNote}',
                                  if (song.notes != null) song.notes,
                                ].join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedSongIds.add(song.id);
                            } else {
                              _selectedSongIds.remove(song.id);
                            }
                          });
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (err, _) => Center(child: Text('Error: $err')),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('song_picker_confirm_button'),
          onPressed: _selectedSongIds.isEmpty
              ? null
              : () => Navigator.pop(context, _selectedSongIds.toList()),
          child: Text(
            _selectedSongIds.isEmpty
                ? 'Select Songs'
                : 'Add ${_selectedSongIds.length} ${_selectedSongIds.length == 1 ? 'Song' : 'Songs'}',
          ),
        ),
      ],
    );
  }
}
