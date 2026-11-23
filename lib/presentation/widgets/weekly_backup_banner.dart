import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:worship_setlist/data/services/backup_service.dart';
import 'package:worship_setlist/domain/backup_manager.dart';

/// State notifier tracking whether the user has dismissed the weekly nudge banner for the current session.
class WeeklyBackupDismissedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
  void reset() => state = false;
}

final weeklyBackupNudgeDismissedProvider =
    NotifierProvider<WeeklyBackupDismissedNotifier, bool>(
      WeeklyBackupDismissedNotifier.new,
    );

/// In-app banner nudging the user to export a backup if no backup was made in the past 7 days (spec.md Section 6).
class WeeklyBackupBanner extends ConsumerWidget {
  final VoidCallback? onBackupPressed;

  const WeeklyBackupBanner({super.key, this.onBackupPressed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDismissed = ref.watch(weeklyBackupNudgeDismissedProvider);
    if (isDismissed) return const SizedBox.shrink();

    final lastBackupAsync = ref.watch(lastBackupTimeStreamProvider);

    return lastBackupAsync.maybeWhen(
      data: (lastBackupAt) {
        final needsNudge = BackupManager.needsWeeklyBackupNudge(
          lastBackupAt: lastBackupAt,
        );

        if (!needsNudge) return const SizedBox.shrink();

        final theme = Theme.of(context);

        return Container(
          key: const Key('weekly_backup_banner'),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.tertiary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.backup_outlined,
                color: theme.colorScheme.onTertiaryContainer,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weekly Backup Reminder',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lastBackupAt == null
                          ? 'Safeguard your songs and playlists by creating your first backup.'
                          : 'You haven\'t backed up your data in over a week.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                key: const Key('banner_backup_button'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () async {
                  if (onBackupPressed != null) {
                    onBackupPressed!();
                  } else {
                    try {
                      await ref.read(backupServiceProvider).shareBackup();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Backup exported successfully!'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Export failed: $e')),
                        );
                      }
                    }
                  }
                },
                child: const Text('Backup'),
              ),
              IconButton(
                key: const Key('banner_dismiss_button'),
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: 'Dismiss reminder',
                onPressed: () {
                  ref
                      .read(weeklyBackupNudgeDismissedProvider.notifier)
                      .dismiss();
                },
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
