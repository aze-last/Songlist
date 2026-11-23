import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_setlist/domain/url_validator.dart';
import 'package:worship_setlist/presentation/providers/songs_provider.dart';

/// Dialog to add a song by pasting an Ultimate Guitar link.
class PasteLinkDialog extends ConsumerStatefulWidget {
  const PasteLinkDialog({super.key});

  @override
  ConsumerState<PasteLinkDialog> createState() => _PasteLinkDialogState();
}

class _PasteLinkDialogState extends ConsumerState<PasteLinkDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _urlController = TextEditingController();
  final _keyNoteController = TextEditingController();
  final _notesController = TextEditingController();

  String? _errorMessage;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _keyNoteController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final error = await ref
        .read(songsControllerProvider.notifier)
        .addSong(
          rawUrl: _urlController.text,
          title: _titleController.text,
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
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Add Song from Link'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMessage != null)
                Container(
                  key: const Key('paste_link_error_banner'),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 18,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              TextFormField(
                key: const Key('paste_link_url_field'),
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Ultimate Guitar Link *',
                  hintText: 'https://tabs.ultimate-guitar.com/tab/...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a URL.';
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
                key: const Key('paste_link_title_field'),
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Song Title *',
                  hintText: 'e.g. Good Good Father',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.music_note),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a title.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('paste_link_keynote_field'),
                controller: _keyNoteController,
                decoration: const InputDecoration(
                  labelText: 'Key note (optional)',
                  hintText: 'e.g. Play in G, Capo 2',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('paste_link_notes_field'),
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'e.g. Intro 4 bars, repeat chorus',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.edit_note),
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
          key: const Key('paste_link_submit_button'),
          onPressed: _isSaving ? null : _handleSubmit,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add Song'),
        ),
      ],
    );
  }
}
