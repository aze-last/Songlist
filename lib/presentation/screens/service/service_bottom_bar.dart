import 'package:flutter/material.dart';
import 'package:worship_setlist/data/database/database.dart';

/// Large touch-target bottom navigation bar for live worship service leading (spec.md Section 5.3).
class ServiceBottomBar extends StatelessWidget {
  final int currentIndex;
  final int totalCount;
  final Song? currentSong;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onOpenJumpList;

  const ServiceBottomBar({
    super.key,
    required this.currentIndex,
    required this.totalCount,
    required this.currentSong,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.onOpenJumpList,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final songTitle = currentSong?.title ?? 'No Song Selected';
    final isLastSong = currentIndex >= totalCount - 1;

    return SafeArea(
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Previous button (large touch target)
            SizedBox(
              height: 52,
              child: FilledButton.tonal(
                key: const Key('service_prev_button'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: canGoPrevious ? onPrevious : null,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_ios_rounded, size: 16),
                    SizedBox(width: 4),
                    Text('Prev', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 6),

            // Center: "N of M · Song title" (Tappable jump list launcher)
            Expanded(
              child: InkWell(
                key: const Key('service_title_jump_button'),
                borderRadius: BorderRadius.circular(10),
                onTap: onOpenJumpList,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              '${currentIndex + 1} of $totalCount',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              songTitle,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.unfold_more_rounded,
                        size: 18,
                        color: theme.colorScheme.outline,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 6),

            // Next button (large touch target)
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('service_next_button'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: canGoNext ? onNext : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isLastSong ? 'End' : 'Next',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      isLastSong
                          ? Icons.check_circle_outline_rounded
                          : Icons.arrow_forward_ios_rounded,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
