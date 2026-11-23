import 'package:flutter/material.dart';

/// Dialog showing download progress and checksum verification status.
class UpdateProgressDialog extends StatelessWidget {
  final double progress;
  final String statusMessage;
  final VoidCallback? onCancel;

  const UpdateProgressDialog({
    super.key,
    required this.progress,
    required this.statusMessage,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = (progress * 100).clamp(0, 100).toInt();

    return AlertDialog(
      key: const Key('update_progress_dialog'),
      title: const Text('Downloading Update'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  statusMessage,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (progress > 0)
                Text(
                  '$percentage%',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ],
      ),
      actions: [
        if (onCancel != null)
          TextButton(
            key: const Key('cancel_download_button'),
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}
