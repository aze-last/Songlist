import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/backup_service.dart';
import '../../data/services/update_service.dart';
import '../../domain/update_checker.dart';
import '../providers/database_provider.dart';
import 'update_dialog.dart';
import 'update_progress_dialog.dart';

/// Coordinates the full user-facing update experience (spec.md Section 8).
///
/// 1. Presents [UpdateDialog] with release notes and version diff.
/// 2. Handles "Skip this version", "Later", or "Update now".
/// 3. Offers a quick backup export prior to updating.
/// 4. Downloads and verifies SHA-256 with [UpdateProgressDialog].
/// 5. Verifies Android unknown sources permission and triggers installation.
Future<void> showUpdateFlow({
  required BuildContext context,
  required WidgetRef ref,
  required ReleaseUpdateInfo releaseInfo,
  required String currentVersion,
}) async {
  final action = await showDialog<UpdateAction>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) =>
        UpdateDialog(currentVersion: currentVersion, releaseInfo: releaseInfo),
  );

  if (!context.mounted || action == null || action == UpdateAction.later) {
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  final db = ref.read(databaseProvider);
  final updateService = ref.read(updateServiceProvider);

  if (action == UpdateAction.skip) {
    await db.updateSettings(skippedVersion: releaseInfo.tagName);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Version ${releaseInfo.tagName} will be skipped.'),
      ),
    );
    return;
  }

  if (action == UpdateAction.updateNow) {
    // Step A: Offer backup export before update
    final shouldExport = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        key: const Key('backup_before_update_dialog'),
        title: const Text('Backup Before Update?'),
        content: const Text(
          'We recommend exporting a backup of your song library and setlists before updating to prevent accidental data loss.',
        ),
        actions: [
          TextButton(
            key: const Key('skip_backup_before_update_button'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Skip Backup'),
          ),
          FilledButton(
            key: const Key('confirm_backup_before_update_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Export Backup'),
          ),
        ],
      ),
    );

    if (!context.mounted || shouldExport == null) return;

    if (shouldExport) {
      try {
        await ref.read(backupServiceProvider).shareBackup();
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not export backup: $e')),
        );
      }
    }

    if (!context.mounted) return;

    // Step B: Download and verify APK
    double downloadProgress = 0.0;
    String statusText = 'Connecting to GitHub...';
    StateSetter? progressSetter;

    // Show Progress Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setState) {
            progressSetter = setState;
            return UpdateProgressDialog(
              progress: downloadProgress,
              statusMessage: statusText,
            );
          },
        );
      },
    );

    File? apkFile;
    try {
      apkFile = await updateService.downloadAndVerifyApk(
        releaseInfo: releaseInfo,
        onProgress: (p) {
          if (progressSetter != null) {
            progressSetter!(() {
              downloadProgress = p;
              statusText = 'Downloading update...';
            });
          }
        },
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss progress
      }
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            key: const Key('update_error_dialog'),
            title: const Text('Update Failed'),
            content: Text(
              e is ChecksumMismatchException
                  ? e.message
                  : 'An error occurred while downloading the update: $e',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // Dismiss progress
    }

    if (apkFile == null || !context.mounted) return;

    // Step C: Permission check and installation
    final canInstall = await updateService.canRequestPackageInstalls();
    if (!canInstall && context.mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const Key('permission_required_dialog'),
          title: const Text('Install Permission Required'),
          content: const Text(
            'Android requires permission to install APK packages from this application. '
            'Please enable "Install unknown apps" in Settings to proceed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('open_install_settings_button'),
              onPressed: () {
                Navigator.of(ctx).pop();
                updateService.openInstallSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      return;
    }

    await updateService.installApk(apkFile.path);
  }
}
