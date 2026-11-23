# PLAN.md — Step 6: Update Feature, Installer, Release Scripts & Keystore Docs

## 1. Spec & Objective
- Problem: As an independent worship setlist tool distributed outside the Play Store, the app needs an in-app updater leveraging public GitHub Releases (download with SHA-256 integrity verification, FileProvider installation) and a reproducible release workflow.
- Hypothesis: Providing a semver-based update service, verified checksum downloader, Android FileProvider installer, release build scripts, and keystore protection ensures seamless and secure ongoing app delivery.
- Invariants & Constraints:
  - Repository coordinates isolated in `lib/config/update_config.dart` (`aze-last`, placeholder `<REPO_NAME>`). Zero tokens/keys.
  - Releases must be public, non-draft, non-prerelease, and contain exactly one `.apk` and one `.sha256` asset.
  - Real semver comparison (`pub_semver`): Never downgrade. Ignore malformed tags. Respect skipped versions.
  - Download restricted to HTTPS allowed GitHub hosts (`github.com`, `objects.githubusercontent.com`, `github-releases.githubusercontent.com`, `api.github.com`).
  - SHA-256 verification: Mismatch or missing checksum deletes the file immediately and aborts. Never install unverified APK.
  - System installation via FileProvider and `REQUEST_INSTALL_PACKAGES`. Guide user if permission not granted.
  - Update dialogs NEVER appear while in Service Mode.
  - Release keystore strictly guarded: release build fails if `android/key.properties` is missing.
  - Release scripts (`scripts/release.ps1` and `scripts/release.sh`) automate versioned APK and `.sha256` artifact generation.
  - Pass `.agents/team/diff-scan.ps1`.

## 2. Scoped Tasks

### T1 — Config & Domain: Semver, Checksum & Host Validation (surface: `lib/config/update_config.dart`, `lib/domain/update_checker.dart`, `test/domain/update_checker_test.dart`)
- Files:
  - `lib/config/update_config.dart`
  - `lib/domain/update_checker.dart`
  - `test/domain/update_checker_test.dart`
- Action:
  - Pure Dart domain class: `UpdateChecker`.
  - Semver evaluation (no downgrade, ignore malformed tags, skip version check).
  - GitHub release JSON parsing (require `.apk` and `.sha256`, reject drafts/prereleases).
  - SHA-256 hash calculation and verification.
  - Host allowlisting.
  - 24-hour throttle calculation.
- Test: Unit tests (RED first) covering all semver edge cases, checksum match/mismatch, host rules, and asset parsing.
- Gate: All unit tests pass.

### T2 — Native Android & Build Configuration (surface: `android/`)
- Files:
  - `android/app/build.gradle.kts`
  - `android/app/src/main/AndroidManifest.xml`
  - `android/app/src/main/res/xml/file_paths.xml`
  - `android/app/src/main/kotlin/com/worship/worship_setlist/MainActivity.kt`
- Action:
  - Add `REQUEST_INSTALL_PACKAGES` and FileProvider in `AndroidManifest.xml`.
  - Create `file_paths.xml` for cache directory exposure.
  - Implement installer MethodChannel in `MainActivity.kt`.
  - Configure `build.gradle.kts` to require `android/key.properties` for release builds.
- Test: Android build script verification and package installation channel bindings.
- Gate: Compiles cleanly.

### T3 — Data & Service: Update Service & Downloader (surface: `lib/data/services/update_service.dart`, `test/data/update_service_test.dart`)
- Files:
  - `lib/data/services/update_service.dart`
  - `test/data/update_service_test.dart`
- Action:
  - `checkForUpdate({bool manual = false})` with mockable HTTP client.
  - Download stream with progress tracking, SHA-256 verification, and abort cleanup on mismatch.
  - Offer backup export option before installing.
- Test: Mocked HTTP tests covering online update detection, up-to-date handling, 404/403/offline handling, checksum match/mismatch file deletion.
- Gate: All tests pass.

### T4 — Presentation: Update Dialogs, Settings Integration & Service Mode Guard (surface: `lib/presentation/`, `test/presentation/update_ui_test.dart`)
- Files:
  - `lib/presentation/widgets/update_dialog.dart`
  - `lib/presentation/widgets/update_progress_dialog.dart`
  - `lib/presentation/screens/settings/settings_screen.dart`
  - `lib/presentation/screens/home_shell.dart`
  - `test/presentation/update_ui_test.dart`
- Action:
  - Dialog displaying release notes, current vs new version, "Update now", "Later", "Skip this version".
  - Wire manual check button in `SettingsScreen`.
  - Wire 24h background auto-check on app launch in `HomeShell`, strictly disabled when in Service Mode.
- Test: Widget tests verifying update dialog actions, version skip persistence, and settings integration.
- Gate: All tests pass.

### T5 — Release Workflow Scripts & Pre-Flight Gate (surface: `scripts/`, `.agents/team/diff-scan.ps1`)
- Files:
  - `scripts/release.ps1`
  - `scripts/release.sh`
- Action:
  - Automate building release APK, computing SHA-256, packaging into `releases/`, and outputting `gh release create` command.
  - Run `.agents/team/diff-scan.ps1`.
- Gate: Exit 0 (`RESULT: GREEN`).
