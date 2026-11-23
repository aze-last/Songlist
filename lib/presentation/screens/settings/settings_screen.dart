import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:worship_setlist/data/services/backup_service.dart';
import 'package:worship_setlist/data/services/update_service.dart';
import 'package:worship_setlist/domain/backup_manager.dart';
import 'package:worship_setlist/domain/date_utils.dart';
import 'package:worship_setlist/presentation/providers/database_provider.dart';
import 'package:worship_setlist/presentation/widgets/update_flow.dart';

/// App settings screen with backup export/import, update checking, and app info (spec.md Section 5.4 & 8).
class SettingsScreen extends ConsumerStatefulWidget {
  final Future<String?> Function()? filePicker;
  final Future<void> Function(String filePath)? shareHandler;

  const SettingsScreen({super.key, this.filePicker, this.shareHandler});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = '1.0.0';
  String _buildNumber = '1';
  bool _isExporting = false;
  bool _isImporting = false;
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = info.version;
          _buildNumber = info.buildNumber;
        });
      }
    } catch (_) {
      // Fallback in headless widget test environments
    }
  }

  Future<void> _handleExport() async {
    setState(() => _isExporting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final service = ref.read(backupServiceProvider);
      if (widget.shareHandler != null) {
        final filePath = await service.exportBackupToFile();
        await widget.shareHandler!(filePath);
      } else {
        await service.shareBackup();
      }

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Backup exported successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to export backup: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _handleImport() async {
    String? selectedFilePath;

    if (widget.filePicker != null) {
      selectedFilePath = await widget.filePicker!();
    } else {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file != null && file.path != null) {
        selectedFilePath = file.path;
      }
    }

    if (selectedFilePath == null || !mounted) return;

    setState(() => _isImporting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final service = ref.read(backupServiceProvider);
      final file = File(selectedFilePath);
      if (!file.existsSync()) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Selected backup file does not exist.'),
            ),
          );
        }
        return;
      }

      final content = file.readAsStringSync();
      final validation = BackupManager.validateAndParse(content);

      if (!validation.isValid) {
        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              key: const Key('backup_validation_error_dialog'),
              title: const Text('Invalid Backup File'),
              content: Text(
                validation.errorMessage ?? 'The selected file could not be parsed as a valid Worship Setlist backup.',
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

      final payload = validation.payload!;

      if (!mounted) return;

      // Mandatory Confirmation Dialog before destructive import (spec.md Section 6 & 7)
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const Key('confirm_restore_dialog'),
          title: const Text('Replace Current Data?'),
          content: Text(
            'Importing this backup will overwrite all existing songs, playlists, and setlists.\n\n'
            'Backup contents:\n'
            '• ${payload.songs.length} ${payload.songs.length == 1 ? 'song' : 'songs'}\n'
            '• ${payload.playlists.length} ${payload.playlists.length == 1 ? 'playlist' : 'playlists'}\n'
            '• ${payload.playlistItems.length} setlist items\n\n'
            'This action cannot be undone. Are you sure you want to proceed?',
          ),
          actions: [
            TextButton(
              key: const Key('cancel_restore_button'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm_replace_button'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Replace & Import'),
            ),
          ],
        ),
      );

      if (confirmed == true && mounted) {
        await service.restoreFromPayload(payload);
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Successfully imported ${payload.songs.length} songs and ${payload.playlists.length} playlists!',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to restore backup: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _handleCheckUpdates() async {
    setState(() => _isCheckingUpdate = true);
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(databaseProvider);
    final updateService = ref.read(updateServiceProvider);

    UpdateCheckResult? result;
    try {
      result = await updateService.checkForUpdate(manual: true);
      // Record check timestamp
      await db.updateSettings(lastUpdateCheck: DateTime.now());
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Error checking for updates: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }

    if (result == null || !mounted) return;

    if (result.status == UpdateCheckStatus.updateAvailable &&
        result.releaseInfo != null) {
      await showUpdateFlow(
        context: context,
        ref: ref,
        releaseInfo: result.releaseInfo!,
        currentVersion: _version,
      );
    } else if (result.status == UpdateCheckStatus.upToDate) {
      messenger.showSnackBar(
        SnackBar(content: Text('App is up to date (v$_version)!')),
      );
    } else if (result.status == UpdateCheckStatus.error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Failed to check for updates.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastBackupAsync = ref.watch(lastBackupTimeStreamProvider);
    final appSettingsAsync = ref.watch(appSettingsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Application Information Card
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Application Info',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'App Version',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        'v$_version+$_buildNumber',
                        key: const Key('app_version_text'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Backup & Restore Card
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.backup_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Backup & Restore',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Export your song library and setlists to avoid data loss.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const Divider(height: 24),

                  // Last Backup Date Row
                  lastBackupAsync.when(
                    data: (lastBackup) => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Last Backup',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          lastBackup != null
                              ? ServiceDateUtils.formatServiceDate(lastBackup)
                              : 'Never',
                          key: const Key('last_backup_date_text'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: lastBackup == null
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    loading: () => const Text('Loading backup info...'),
                    error: (_, _) => const SizedBox.shrink(),
                  ),

                  const SizedBox(height: 16),

                  // Export & Import Buttons
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('export_backup_button'),
                          onPressed: _isExporting ? null : _handleExport,
                          icon: _isExporting
                              ? const Icon(
                                  Icons.hourglass_top_rounded,
                                  size: 18,
                                )
                              : const Icon(Icons.share_outlined),
                          label: const Text('Export Backup'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('import_backup_button'),
                          onPressed: _isImporting ? null : _handleImport,
                          icon: _isImporting
                              ? const Icon(
                                  Icons.hourglass_top_rounded,
                                  size: 18,
                                )
                              : const Icon(Icons.file_upload_outlined),
                          label: const Text('Import Backup'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Updates Card (spec.md Section 8)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.system_update_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Updates',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'GitHub Releases',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Check for new APK versions on GitHub',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        key: const Key('check_updates_button'),
                        onPressed: _isCheckingUpdate
                            ? null
                            : _handleCheckUpdates,
                        child: _isCheckingUpdate
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Check'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  appSettingsAsync.when(
                    data: (settings) => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Last Checked',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          settings?.lastUpdateCheck != null
                              ? ServiceDateUtils.formatServiceDate(
                                  settings!.lastUpdateCheck!,
                                )
                              : 'Never',
                          key: const Key('last_update_check_text'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
