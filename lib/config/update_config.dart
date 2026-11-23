/// Remote update configuration (spec.md Section 8).
///
/// Contains repository coordinates for checking public GitHub releases.
/// Zero secrets, tokens, or private credentials.
class UpdateConfig {
  static const String githubOwner = 'aze-last';
  static const String githubRepo = 'Songlist';

  static String get releasesLatestUrl =>
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';
}
