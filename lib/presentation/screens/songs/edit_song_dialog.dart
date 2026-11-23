import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/domain/url_validator.dart';
import 'package:worship_setlist/presentation/providers/songs_provider.dart';

/// Modal dialog to edit an existing song's details.
class EditSongDialog extends ConsumerStatefulWidget {
  final Song song;

  const EditSongDialog({super.key, required this.song});

  @override
  ConsumerState<EditSongDialog> createState() => _EditSongDialogState();
}

class _EditSongDialogState extends ConsumerState<EditSongDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _urlController;
  late final TextEditingController _keyNoteController;
  late final TextEditingController _notesController;

  String? _errorMessage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.song.title);
    _urlController = TextEditingController(text: widget.song.url);
    _keyNoteController = TextEditingController(text: widget.song.keyNote ?? '');
    _notesController = TextEditingController(text: widget.song.notes ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _keyNoteController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final error = await ref
        .read(songsControllerProvider.notifier)
        .updateSong(
          id: widget.song.id,
          title: _titleController.text,
          rawUrl: _urlController.text,
          keyNote: _keyNoteController.text,
          notes: _notesController.text,
        );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (error != null) {
      setState(() => _errorMessage = error);
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Song'),
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
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  hintText: 'e.g. 10,000 Reasons',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a song title.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Ultimate Guitar URL *',
                  hintText: 'https://tabs.ultimate-guitar.com/tab/...',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a UG URL.';
                  }
                  final result = UrlValidator.validateAndNormalize(val);
                  if (!result.isValid) {
                    return result.errorMessage;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _keyNoteController,
                decoration: const InputDecoration(
                  labelText: 'Key note (displayed in service)',
                  hintText: 'e.g. Play in G, Capo 2',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'e.g. Intro 4 bars, repeat bridge',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _handleSave,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
