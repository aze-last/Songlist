import 'package:flutter/material.dart';

import '../../domain/update_checker.dart';

enum UpdateAction { updateNow, later, skip }

/// Dialog shown when a newer version is available on GitHub Releases (spec.md Section 8).
class UpdateDialog extends StatelessWidget {
  final String currentVersion;
  final ReleaseUpdateInfo releaseInfo;

  const UpdateDialog({
    super.key,
    required this.currentVersion,
    required this.releaseInfo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = releaseInfo.releaseNotes.trim().isNotEmpty
        ? releaseInfo.releaseNotes.trim()
        : 'Bug fixes and performance improvements.';

    return AlertDialog(
      key: const Key('update_dialog'),
      title: Row(
        children: [
          Icon(Icons.system_update_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('New Update Available'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Version',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      Text(
                        currentVersion,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'New Version',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      Text(
                        releaseInfo.tagName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Release Notes:',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 180),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(notes, style: theme.textTheme.bodySmall),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('skip_version_button'),
          onPressed: () => Navigator.of(context).pop(UpdateAction.skip),
          child: const Text('Skip this version'),
        ),
        TextButton(
          key: const Key('update_later_button'),
          onPressed: () => Navigator.of(context).pop(UpdateAction.later),
          child: const Text('Later'),
        ),
        FilledButton(
          key: const Key('update_now_button'),
          onPressed: () => Navigator.of(context).pop(UpdateAction.updateNow),
          child: const Text('Update now'),
        ),
      ],
    );
  }
}
