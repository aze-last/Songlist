/// Pure Dart URL validation and normalization for Ultimate Guitar (UG) URLs.
///
/// Complies with spec.md Sections 1, 3, and 5.1:
/// - Only HTTPS allowed.
/// - Allowed hosts: tabs.ultimate-guitar.com, www.ultimate-guitar.com.
/// - Path must begin with /tab/.
/// - Normalization strips query parameters, tracking parameters, and fragments.
class UrlValidationResult {
  final bool isValid;
  final String? normalizedUrl;
  final String? errorMessage;

  const UrlValidationResult({
    required this.isValid,
    this.normalizedUrl,
    this.errorMessage,
  });

  factory UrlValidationResult.valid(String normalizedUrl) =>
      UrlValidationResult(isValid: true, normalizedUrl: normalizedUrl);

  factory UrlValidationResult.invalid(String errorMessage) =>
      UrlValidationResult(isValid: false, errorMessage: errorMessage);
}

class UrlValidator {
  static const Set<String> allowedHosts = {
    'tabs.ultimate-guitar.com',
    'www.ultimate-guitar.com',
  };

  /// Checks if a host is in the allowed UG hosts list.
  static bool isAllowedHost(String? host) {
    if (host == null || host.isEmpty) return false;
    return allowedHosts.contains(host.toLowerCase().trim());
  }

  /// Validates and normalizes an input URL.
  static UrlValidationResult validateAndNormalize(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return UrlValidationResult.invalid('URL cannot be empty.');
    }

    Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return UrlValidationResult.invalid('Malformed URL format.');
    }

    if (!uri.hasScheme || uri.scheme.toLowerCase() != 'https') {
      return UrlValidationResult.invalid(
        'Invalid scheme: HTTPS is required (received: ${uri.scheme.isEmpty ? "none" : uri.scheme}).',
      );
    }

    final host = uri.host.toLowerCase();
    if (!isAllowedHost(host)) {
      return UrlValidationResult.invalid(
        'Host must be ultimate-guitar.com (allowed: tabs.ultimate-guitar.com, www.ultimate-guitar.com). Received: $host',
      );
    }

    // Path normalization: normalize slashes
    var path = uri.path;
    if (!path.startsWith('/')) {
      path = '/$path';
    }

    if (!path.startsWith('/tab/')) {
      return UrlValidationResult.invalid(
        'Path must start with /tab/ (received: $path).',
      );
    }

    // Strip trailing slashes after the tab path
    var normalizedPath = path;
    while (normalizedPath.length > 5 && normalizedPath.endsWith('/')) {
      normalizedPath = normalizedPath.substring(0, normalizedPath.length - 1);
    }

    // Build normalized URL: scheme + host + clean path (no query, no fragment)
    final normalized = Uri(
      scheme: 'https',
      host: host,
      path: normalizedPath,
    ).toString();

    return UrlValidationResult.valid(normalized);
  }

  /// Returns true if two raw URLs normalize to the same canonical UG tab URL.
  static bool areDuplicate(String url1, String url2) {
    final res1 = validateAndNormalize(url1);
    final res2 = validateAndNormalize(url2);
    if (!res1.isValid || !res2.isValid) return false;
    return res1.normalizedUrl == res2.normalizedUrl;
  }
}
