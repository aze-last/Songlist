import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/domain/date_utils.dart';
import 'package:worship_setlist/presentation/providers/playlists_provider.dart';

/// Modal dialog to duplicate an existing playlist ("Copy as new Sunday").
class DuplicatePlaylistDialog extends ConsumerStatefulWidget {
  final Playlist playlist;

  const DuplicatePlaylistDialog({super.key, required this.playlist});

  @override
  ConsumerState<DuplicatePlaylistDialog> createState() =>
      _DuplicatePlaylistDialogState();
}

class _DuplicatePlaylistDialogState
    extends ConsumerState<DuplicatePlaylistDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late DateTime _selectedDate;
  bool _isDuplicating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Default to the following Sunday after the source playlist date
    _selectedDate = ServiceDateUtils.getNextSunday(widget.playlist.serviceDate);
    _nameController = TextEditingController(
      text: '${widget.playlist.name} (Copy)',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Future<void> _handleDuplicate() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isDuplicating = true);

    try {
      final newId = await ref
          .read(playlistsControllerProvider.notifier)
          .duplicatePlaylist(
            sourcePlaylistId: widget.playlist.id,
            newName: _nameController.text,
            newServiceDate: _selectedDate,
          );

      if (!mounted) return;
      Navigator.of(context).pop(newId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDuplicating = false;
        _errorMessage = 'Failed to duplicate playlist: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Copy as New Sunday'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontSize: 13,
                    ),
                  ),
                ),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'New Playlist Name *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.playlist_play_rounded),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a name.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_rounded),
                title: const Text('Target Sunday Date'),
                subtitle: Text(
                  ServiceDateUtils.formatServiceDate(_selectedDate),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: TextButton(
                  onPressed: _pickDate,
                  child: const Text('Change'),
                ),
                onTap: _pickDate,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDuplicating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isDuplicating ? null : _handleDuplicate,
          child: _isDuplicating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Duplicate'),
        ),
      ],
    );
  }
}
