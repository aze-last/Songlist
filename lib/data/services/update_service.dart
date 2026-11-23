import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../config/update_config.dart';
import '../../domain/update_checker.dart';
import '../../presentation/providers/database_provider.dart';
import '../database/database.dart';

/// Thrown when the downloaded APK SHA-256 checksum does not match the release checksum file.
class ChecksumMismatchException implements Exception {
  final String message;
  const ChecksumMismatchException(this.message);

  @override
  String toString() => 'ChecksumMismatchException: $message';
}

/// Status of an update check attempt.
enum UpdateCheckStatus { updateAvailable, upToDate, throttled, error }

/// Result of an update check.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    this.releaseInfo,
    this.errorMessage,
  });

  final UpdateCheckStatus status;
  final ReleaseUpdateInfo? releaseInfo;
  final String? errorMessage;
}

/// Service that coordinates update checking, downloading with SHA-256 integrity
/// verification, and launching Android APK installation via platform channel.
class UpdateService {
  UpdateService({
    http.Client? httpClient,
    this.currentVersion,
    this.skippedVersion,
    this.lastCheckAt,
    this.githubOwner,
    this.githubRepo,
    this.releasesUrl,
    this.tempDirProvider,
    this.onInstallApk,
    this.onCanRequestInstalls,
    this.onOpenInstallSettings,
  }) : _client = httpClient ?? http.Client();

  static const MethodChannel _installerChannel = MethodChannel(
    'com.worship.setlist/app_installer',
  );

  final http.Client _client;
  final String? currentVersion;
  final String? skippedVersion;
  final DateTime? lastCheckAt;
  final String? githubOwner;
  final String? githubRepo;
  final String? releasesUrl;
  final Future<Directory> Function()? tempDirProvider;
  final Future<bool> Function(String filePath)? onInstallApk;
  final Future<bool> Function()? onCanRequestInstalls;
  final Future<bool> Function()? onOpenInstallSettings;

  String get effectiveOwner => githubOwner ?? UpdateConfig.githubOwner;
  String get effectiveRepo => githubRepo ?? UpdateConfig.githubRepo;
  String get effectiveReleasesUrl {
    final url = releasesUrl;
    if (url != null) return url;
    return 'https://api.github.com/repos/$effectiveOwner/$effectiveRepo/releases/latest';
  }

  static ReleaseUpdateInfo? parseReleaseInfo(Map<String, dynamic> json) =>
      UpdateChecker.parseRelease(json);

  Future<Directory> _getTempDir() async {
    final provider = tempDirProvider;
    if (provider != null) {
      return await provider();
    }
    return await getTemporaryDirectory();
  }

  /// Checks for available updates from GitHub Releases.
  ///
  /// Set [manual] to true to bypass the 24-hour throttle.
  Future<UpdateCheckResult> checkForUpdate({
    bool manual = false,
    String? skippedVersion,
    DateTime? lastCheckAt,
  }) async {
    final checkAt = lastCheckAt ?? this.lastCheckAt;
    final skipVer = skippedVersion ?? this.skippedVersion;

    if (!manual) {
      if (!UpdateChecker.shouldAutoCheck(lastCheckAt: checkAt)) {
        return const UpdateCheckResult(status: UpdateCheckStatus.throttled);
      }
    }

    if (effectiveRepo == '<REPO_NAME>' ||
        effectiveRepo.trim().isEmpty ||
        effectiveOwner.trim().isEmpty) {
      return const UpdateCheckResult(
        status: UpdateCheckStatus.error,
        errorMessage: 'Repository not configured (set in update_config.dart).',
      );
    }

    try {
      final uri = Uri.parse(effectiveReleasesUrl);
      final response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'WorshipSetlistApp',
        },
      );

      if (response.statusCode == 404) {
        return const UpdateCheckResult(
          status: UpdateCheckStatus.error,
          errorMessage:
              'No releases found for this repository on GitHub (HTTP 404).',
        );
      } else if (response.statusCode == 403) {
        return const UpdateCheckResult(
          status: UpdateCheckStatus.error,
          errorMessage: 'GitHub API rate limit exceeded. Please try again later (HTTP 403).',
        );
      } else if (response.statusCode != 200) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.error,
          errorMessage: 'HTTP ${response.statusCode}: ${response.body}',
        );
      }

      final releaseJson = jsonDecode(response.body) as Map<String, dynamic>;
      final releaseInfo = UpdateChecker.parseRelease(releaseJson);

      if (releaseInfo == null) {
        return const UpdateCheckResult(
          status: UpdateCheckStatus.error,
          errorMessage: 'Release found, but matching APK and SHA-256 checksum assets are missing or incomplete.',
        );
      }

      var versionToCompare = currentVersion;
      if (versionToCompare == null || versionToCompare.trim().isEmpty) {
        try {
          final info = await PackageInfo.fromPlatform();
          versionToCompare = info.version;
        } catch (_) {
          versionToCompare = '1.0.0';
        }
      }

      final hasUpdate = UpdateChecker.isNewerVersion(
        currentVersion: versionToCompare,
        latestTag: releaseInfo.tagName,
        skippedVersion: skipVer,
      );

      if (hasUpdate) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.updateAvailable,
          releaseInfo: releaseInfo,
        );
      } else {
        return UpdateCheckResult(
          status: UpdateCheckStatus.upToDate,
          releaseInfo: releaseInfo,
        );
      }
    } catch (e) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.error,
        errorMessage: 'Failed to check for updates: $e',
      );
    }
  }

  /// Downloads the release APK and verifies its integrity against the SHA-256 checksum.
  ///
  /// If the SHA-256 does not match, the file is deleted immediately and
  /// [ChecksumMismatchException] is thrown.
  Future<File?> downloadAndVerifyApk({
    required ReleaseUpdateInfo releaseInfo,
    void Function(double progress)? onProgress,
  }) async {
    if (!UpdateChecker.isAllowedDownloadUrl(releaseInfo.apkDownloadUrl) ||
        !UpdateChecker.isAllowedDownloadUrl(releaseInfo.sha256DownloadUrl)) {
      throw const FormatException(
        'Download URL is not an authorized GitHub domain.',
      );
    }

    // Step 1: Fetch SHA-256 content
    final shaResponse = await _client.get(
      Uri.parse(releaseInfo.sha256DownloadUrl),
      headers: {'User-Agent': 'WorshipSetlistApp'},
    );
    if (shaResponse.statusCode != 200) {
      throw HttpException(
        'Failed to download SHA-256 checksum file (HTTP ${shaResponse.statusCode}).',
      );
    }
    final shaContent = shaResponse.body;

    // Step 2: Stream download the APK
    final tempDir = await _getTempDir();
    final apkFile = File('${tempDir.path}/${releaseInfo.apkAssetName}');

    final request = http.Request('GET', Uri.parse(releaseInfo.apkDownloadUrl))
      ..headers['User-Agent'] = 'WorshipSetlistApp';
    final streamedResponse = await _client.send(request);

    if (streamedResponse.statusCode != 200) {
      throw HttpException(
        'Failed to download APK file (HTTP ${streamedResponse.statusCode}).',
      );
    }

    final totalBytes = streamedResponse.contentLength ?? releaseInfo.apkSize;
    var receivedBytes = 0;
    final sink = apkFile.openWrite();

    try {
      await streamedResponse.stream.listen((chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          onProgress(receivedBytes / totalBytes);
        }
      }).asFuture();
    } finally {
      await sink.flush();
      await sink.close();
    }

    // Step 3: Verify SHA-256
    final apkBytes = await apkFile.readAsBytes();
    final isValid = UpdateChecker.verifyChecksum(
      fileBytes: apkBytes,
      checksumFileContent: shaContent,
    );

    if (!isValid) {
      if (apkFile.existsSync()) {
        try {
          apkFile.deleteSync();
        } catch (_) {}
      }
      throw const ChecksumMismatchException(
        'Downloaded APK SHA-256 checksum does not match official release. Installation aborted.',
      );
    }

    return apkFile;
  }

  /// Checks if the app has permission to request package installs.
  Future<bool> canRequestPackageInstalls() async {
    final callback = onCanRequestInstalls;
    if (callback != null) {
      return await callback();
    }
    try {
      final result = await _installerChannel.invokeMethod<bool>(
        'canRequestPackageInstalls',
      );
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Opens the Android system settings page for unknown app sources.
  Future<bool> openInstallSettings() async {
    final callback = onOpenInstallSettings;
    if (callback != null) {
      return await callback();
    }
    try {
      final result = await _installerChannel.invokeMethod<bool>(
        'openInstallSettings',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Triggers Android package installer for the specified APK file.
  Future<bool> installApk(String filePath) async {
    final callback = onInstallApk;
    if (callback != null) {
      return await callback(filePath);
    }
    try {
      final result = await _installerChannel.invokeMethod<bool>('installApk', {
        'filePath': filePath,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Removes any cached .apk files from previous downloads.
  Future<void> deleteCachedApks() async {
    try {
      final tempDir = await _getTempDir();
      if (!tempDir.existsSync()) return;
      final entities = tempDir.listSync();
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.apk')) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

final appSettingsStreamProvider = StreamProvider<AppSetting?>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.appSettings,
  )..where((s) => s.id.equals(1))).watchSingleOrNull();
});
