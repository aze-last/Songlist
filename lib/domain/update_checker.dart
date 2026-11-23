import 'package:crypto/crypto.dart';
import 'package:pub_semver/pub_semver.dart';

/// Structured information parsed from a GitHub release for an update.
class ReleaseUpdateInfo {
  const ReleaseUpdateInfo({
    required this.tagName,
    required this.releaseNotes,
    required this.apkAssetName,
    required this.apkDownloadUrl,
    required this.apkSize,
    required this.sha256AssetName,
    required this.sha256DownloadUrl,
  });

  final String tagName;
  final String releaseNotes;
  final String apkAssetName;
  final String apkDownloadUrl;
  final int apkSize;
  final String sha256AssetName;
  final String sha256DownloadUrl;
}

/// Pure Dart domain logic for version comparison, release parsing,
/// URL security rules, and checksum verification. Zero Flutter dependencies.
class UpdateChecker {
  const UpdateChecker._();

  static const List<String> allowedHosts = [
    'github.com',
    'objects.githubusercontent.com',
    'github-releases.githubusercontent.com',
    'api.github.com',
  ];

  /// Checks if [latestTag] is semantically newer than [currentVersion].
  ///
  /// Ignores leading 'v' or 'V'.
  /// Ignores build metadata suffixes during comparison.
  /// If [skippedVersion] matches [latestTag], returns false.
  static bool isNewerVersion({
    required String currentVersion,
    required String latestTag,
    String? skippedVersion,
  }) {
    if (latestTag.trim().isEmpty) return false;

    // Check if the user opted to skip this tag/version
    if (skippedVersion != null && skippedVersion.trim().isNotEmpty) {
      if (_cleanVersionString(skippedVersion) ==
              _cleanVersionString(latestTag) ||
          skippedVersion.trim() == latestTag.trim()) {
        return false;
      }
    }

    try {
      final cleanCurrent = _cleanVersionString(currentVersion);
      final cleanLatest = _cleanVersionString(latestTag);

      final current = Version.parse(cleanCurrent);
      final latest = Version.parse(cleanLatest);

      // Compare base versions without build metadata
      final baseCurrent = Version(
        current.major,
        current.minor,
        current.patch,
        pre: current.preRelease.join('.'),
      );
      final baseLatest = Version(
        latest.major,
        latest.minor,
        latest.patch,
        pre: latest.preRelease.join('.'),
      );

      return baseLatest > baseCurrent;
    } catch (_) {
      // In case of any malformed semver string, safely ignore
      return false;
    }
  }

  /// Strips leading 'v'/'V' and extracts standard semver.
  static String _cleanVersionString(String ver) {
    var trimmed = ver.trim();
    if (trimmed.startsWith('v') || trimmed.startsWith('V')) {
      trimmed = trimmed.substring(1);
    }
    return trimmed;
  }

  /// Parses a GitHub Release JSON object.
  /// Returns null if release is draft, prerelease, or missing required assets.
  static ReleaseUpdateInfo? parseRelease(Map<String, dynamic> releaseJson) {
    if (releaseJson['draft'] == true || releaseJson['prerelease'] == true) {
      return null;
    }

    final tagName = releaseJson['tag_name'] as String?;
    if (tagName == null || tagName.trim().isEmpty) {
      return null;
    }

    final releaseNotes = (releaseJson['body'] as String?) ?? '';
    final assetsList = releaseJson['assets'] as List<dynamic>?;
    if (assetsList == null) return null;

    Map<String, dynamic>? apkAsset;
    Map<String, dynamic>? sha256Asset;

    for (final item in assetsList) {
      if (item is! Map<String, dynamic>) continue;
      final name = (item['name'] as String?)?.toLowerCase() ?? '';
      if (name.endsWith('.apk')) {
        apkAsset = item;
      } else if (name.endsWith('.sha256')) {
        sha256Asset = item;
      }
    }

    if (apkAsset == null || sha256Asset == null) {
      return null;
    }

    final apkUrl = apkAsset['browser_download_url'] as String?;
    final sha256Url = sha256Asset['browser_download_url'] as String?;

    if (apkUrl == null || sha256Url == null) {
      return null;
    }

    return ReleaseUpdateInfo(
      tagName: tagName,
      releaseNotes: releaseNotes,
      apkAssetName: (apkAsset['name'] as String?) ?? 'app.apk',
      apkDownloadUrl: apkUrl,
      apkSize: (apkAsset['size'] as int?) ?? 0,
      sha256AssetName: (sha256Asset['name'] as String?) ?? 'app.apk.sha256',
      sha256DownloadUrl: sha256Url,
    );
  }

  /// Checks if [url] is HTTPS and hosted on an authorized GitHub domain.
  static bool isAllowedDownloadUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme.toLowerCase() != 'https') return false;

    final host = uri.host.toLowerCase();
    return allowedHosts.contains(host);
  }

  /// Verifies [fileBytes] against the SHA-256 hash in [checksumFileContent].
  ///
  /// Supports raw 64-char hashes or standard `hash  filename` format.
  static bool verifyChecksum({
    required List<int> fileBytes,
    required String checksumFileContent,
  }) {
    final hashRegex = RegExp(r'[a-fA-F0-9]{64}');
    final match = hashRegex.firstMatch(checksumFileContent);
    if (match == null) return false;

    final expectedHash = match.group(0)!.toLowerCase();
    final actualHash = sha256.convert(fileBytes).toString().toLowerCase();

    return actualHash == expectedHash;
  }

  /// Determines whether 24 hours have elapsed since [lastCheckAt].
  static bool shouldAutoCheck({required DateTime? lastCheckAt, DateTime? now}) {
    if (lastCheckAt == null) return true;
    final currentTime = now ?? DateTime.now();
    return currentTime.difference(lastCheckAt).inHours >= 24;
  }
}
