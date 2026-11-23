# PLAN.md — Step 2: Songs Library, "Browse UG" & "Paste Link"

## 1. Spec & Objective
- Problem: The app needs a complete Song library interface allowing musicians to search, view, edit, and archive songs, plus two distinct methods to add songs: "Paste link" with instant normalization & duplicate prevention, and "Browse UG" via a secure, sandboxed in-app WebView.
- Hypothesis: Providing a Material 3 songs list with reactive Riverpod state, instant URL validation, and a strict WebView browser allows users to build their setlist catalog while adhering to all UG compliance rules.
- Invariants & Constraints:
  - WebView isolation: Navigation strictly allowed only to `tabs.ultimate-guitar.com` and `www.ultimate-guitar.com` over HTTPS.
  - Zero JavaScript channels, zero injected scraping scripts, file access and content access disabled in WebView.
  - Non-UG links intercepted and offered to open in external system browser.
  - "Save this song" enabled ONLY when current URL path starts with `/tab/`.
  - Duplicate detection by normalized URL with helpful feedback.
  - Confirm dialog before archiving.
  - Portrait lock and Material 3 theme in `main.dart`.

## 2. Scoped Tasks

### T1 — State Layer: Riverpod Database & Song Providers (surface: `lib/presentation/providers/`, `test/presentation/songs_provider_test.dart`)
- Files: `lib/presentation/providers/database_provider.dart`, `lib/presentation/providers/songs_provider.dart`, `test/presentation/songs_provider_test.dart`
- Action:
  - Create Riverpod providers for `AppDatabase`, `songsListStreamProvider`, `songSearchQueryProvider`, and `filteredSongsProvider`.
  - Provide helper methods for adding (with duplicate check), editing, archiving, and restoring songs.
- Test: Unit tests (RED first) validating filtered search results, duplicate URL rejection, and reactive archiving.
- Gate: All tests pass.

### T2 — UI: Songs Library Screen & Edit/Archive Dialogs (surface: `lib/presentation/screens/songs/`)
- Files: `lib/presentation/screens/songs/songs_screen.dart`, `lib/presentation/screens/songs/edit_song_dialog.dart`, `lib/presentation/screens/songs/song_card.dart`
- Action:
  - Build searchable songs list showing title, key note chip, and notes preview.
  - Add confirmation dialog before archiving ("Archive song?").
  - Add Edit dialog to modify title, URL, notes, and key note.
  - FloatingActionButton with menu or bottom sheet: "Browse UG" and "Paste Link".
- Test: Widget tests verifying search filtering, archive confirmation, and edit dialog interactions.
- Gate: Widget tests pass.

### T3 — UI: "Paste Link" Dialog (surface: `lib/presentation/screens/songs/paste_link_dialog.dart`, `test/presentation/paste_link_test.dart`)
- Files: `lib/presentation/screens/songs/paste_link_dialog.dart`, `test/presentation/paste_link_test.dart`
- Action:
  - Form with URL, Title, Key note, and Notes inputs.
  - Real-time/on-submit validation using `UrlValidator.validateAndNormalize`.
  - Check for duplicate normalized URLs in the database; show error if already in library.
  - Save valid song and close.
- Test: Widget tests (RED first) covering valid submission, invalid URL error display, and duplicate URL error display.
- Gate: All tests pass.

### T4 — UI: "Browse UG" In-App WebView Screen (surface: `lib/presentation/screens/songs/browse_ug_screen.dart`, `test/presentation/browse_ug_test.dart`)
- Files: `lib/presentation/screens/songs/browse_ug_screen.dart`, `test/presentation/browse_ug_test.dart`
- Action:
  - Configure `WebViewController`:
    - JavaScriptMode.unrestricted (UG requires JS).
    - Navigation delegate: allow only HTTPS on `tabs.ultimate-guitar.com` and `www.ultimate-guitar.com`.
    - Block all other URLs and display prompt: "Open external link in browser?" using `url_launcher`.
    - Android platform specific: disable file access (`setAllowFileAccess(false)`) and content access (`setAllowContentAccess(false)`).
    - Handle loading errors with offline/error view and "Retry" button.
  - Persistent bottom/top action: "Save this song".
    - Active only when current URL path starts with `/tab/`.
    - On tap, captures current URL and page title, presents a confirmation bottom sheet to review/edit Title, Key note, Notes before saving.
    - Rejects duplicates by normalized URL.
- Test: Tests verifying navigation policy (allow UG, block third-party), error handler, and tab path check.
- Gate: All tests pass.

### T5 — Application Root & Orientation Lock (surface: `lib/main.dart`)
- Files: `lib/main.dart`
- Action:
  - Lock portrait orientations (`portraitUp`, `portraitDown`).
  - Configure Material 3 `ThemeData`.
  - Wrap app in `ProviderScope`.
  - Set `SongsScreen` as home screen.
- Gate: `flutter analyze` passes cleanly.

### T6 — Pre-Flight Gate Verification (surface: `.agents/team/diff-scan.ps1`)
- Action: Run `diff-scan.ps1` to ensure `dart format`, `flutter analyze`, and `flutter test` are completely GREEN.
- Gate: Exit 0 (`RESULT: GREEN`).

## 3. Edge Cases & Safety
- WebView Host Enforcement: Host check must be case-insensitive and strictly match the two allowed domains. Subdomains other than `tabs` or `www` (e.g. `malicious.ultimate-guitar.com.attacker.com` or `forum.ultimate-guitar.com`) must be blocked.
- Duplicate Detection: Normalize URLs before querying database to avoid storing multiple entries for URLs differing only by query parameters or hash fragments.
- Offline Handling: In the WebView, when `onWebResourceError` is triggered, show a clear retry screen instead of crashing or showing a blank page.
