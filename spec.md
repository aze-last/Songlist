# SPEC: Worship Setlist (Flutter, Android, single user)
# Sanity check: Every time you work on this project, you must read this file first. Every finish query You'll gonna mentioned my Name: BIEN!!!

Baseline for the AI coder and the code reviewer. If code contradicts this file, the code is wrong unless this file is updated first. Rename this file to `spec.md` in the new repo.

## 1. Scope

- Single-user Android app (Flutter/Dart), portrait only, English UI. No login, no backend, no sync.
- Purpose: keep a list of songs as links to Ultimate Guitar (UG) pages, arrange them into a playlist for each Sunday, and move through the playlist with Next/Previous while the song is shown in an in-app WebView.
- The app stores ONLY: song title, UG URL, the user's own short notes, playlists, and settings. It does NOT store, copy, cache, parse, extract, or screenshot UG content (no lyrics, no chords, no PDFs, no HTML).
- Requires internet to view a song. Song list and playlists (browse, edit, reorder) work offline. Viewing a song offline shows a clear "No internet" screen with a Retry button.
- Out of scope for v1: PDF attachment or import, text extraction, in-app transpose, offline song display, multi-user, sync, iOS, tablets/landscape, preloading the next song.
- Network allowlist (nothing else is allowed): `tabs.ultimate-guitar.com` and `www.ultimate-guitar.com` (WebView navigation only), and GitHub hosts for the update feature (section 8).
- No API keys, tokens, or secrets anywhere in the app or repo. If a backend is ever added, secrets stay server-side, never in the APK.

## 2. Tech

- Flutter + Dart, Material 3, portrait lock. Project name: `worship_setlist` (application ID: `com.worship.setlist`).
- WebView: `webview_flutter` (current maintained version).
- Local SQLite via `drift` (selected). State: `flutter_riverpod` (selected).
- Keep the screen awake in Service mode (`wakelock_plus` or equivalent).
- Layers: `lib/domain/` (pure Dart: URL validation, playlist ordering logic, semver; no Flutter imports), `lib/data/` (DB, repositories, services), `lib/presentation/` (screens, widgets, providers), `lib/config/update_config.dart`.
- Engineering discipline & quality gate: bound by `.agents/rules.md`. Code changes must pass `.agents/team/diff-scan.ps1` (checking `dart format`, `flutter analyze`, and `flutter test`). TDD (RED -> GREEN -> IMPROVE) mandatory for all domain and data logic.

## 3. WebView rules

- JavaScript enabled (UG needs it). Navigation allowed only to the two UG hosts over HTTPS. Any other link: block it, and offer "Open in browser" via the system browser.
- No JavaScript channels. The page must never be able to call into the app.
- Do not inject JavaScript to read, scrape, modify, or hide page content (no ad-blocking in v1).
- Disable file access and content access from the WebView.
- Cookies and login session persist normally so a UG login, if the user ever adds one, stays.
- Handle load errors (offline, timeout, HTTP error) with a friendly screen and Retry. Never crash.
- UG's own on-page controls (including its transpose control, if available to the user's account) are the only transpose. The app does not drive them and does not remember their state.

## 4. Data model

```
songs(id, title, url, notes, key_note, created_at, archived)
playlists(id, name, service_date, created_at)
playlist_items(id, playlist_id, song_id, position)
settings(last_update_check, skipped_version, last_backup_at)
```

- `notes`: free text from the user (e.g. "intro 4 bars, repeat chorus twice").
- `key_note`: short free text the user types (e.g. "Play in G, capo 2"). The app displays it in Service mode. It is not computed.
- Archive songs, never hard-delete (old playlists must stay intact). Deleting a playlist removes only its items.
- `position` is contiguous 0..n-1 per playlist; renormalize after every move or removal. A song may appear twice in one playlist (assumption, see section 11).
- Multi-row writes use transactions. Index `playlist_items(playlist_id, position)` and `playlists(service_date)`.

## 5. Screens

### 5.1 Songs (library)
- List with search by title. Add, edit (title, URL, notes, key_note), archive/restore (confirm before archive).
- Add song, two ways:
  1. "Browse UG": opens UG in the in-app WebView. A persistent "Save this song" button captures the current URL and page title (editable before saving). Only song pages (path starts with `/tab/`) can be saved.
  2. "Paste link": validate that the URL is HTTPS, host is an allowed UG host, and path starts with `/tab/`. Normalize (strip tracking query strings and fragments). Title is typed by the user.
- Reject duplicates by normalized URL, with a message pointing to the existing song.

### 5.2 Playlists
- List by service date (newest first). Create (default date: next Sunday), rename, change date, delete (confirm), duplicate ("Copy as new Sunday", defaulting to the next date).
- Playlist detail: add songs (searchable picker, multi-select), drag to reorder, swipe/button to remove, per-row quick view of key_note and notes.
- Show total song count. A "Start service" button opens Service mode at position 0 (or at the last position, with a prompt to resume).

### 5.3 Service mode (core screen)
- Full-screen WebView of the current song's URL.
- Bottom bar: Previous | "N of M · Song title" | Next. Large touch targets (one-handed use).
- Tapping the title opens a jump list of the playlist to go straight to any song.
- Show key_note and notes in a collapsible panel above the bar.
- Next on the last song shows "End of playlist" and disables Next. Previous on the first song is disabled.
- Screen stays awake. Back press asks "Leave service mode?" to prevent accidental exits.
- Remember the last position per playlist.
- Update dialogs never appear in Service mode (show a banner after leaving).

### 5.4 Settings
- Installed version and build, "Check for updates" button, backup export/import, weekly backup nudge.

## 6. Backup (required)

- Export songs, playlists, and playlist_items to one JSON file through the Android share sheet, with a `schema_version`.
- Import validates the file, warns that it replaces current data, and requires confirmation.
- Local data loss on phone loss or reset is the main risk. Nudge a weekly export with an in-app banner.

## 7. Validation

- Title and URL required. URL rules in 5.1. Playlist name or date required. No negative positions. Confirm before delete, archive, import, or leaving Service mode.

## 8. Update feature (GitHub Releases)

- `lib/config/update_config.dart`: `githubOwner = "aze-last"`, `githubRepo = "<REPO_NAME>"` (placeholder). Nothing else hardcodes the repo. The repo must be public. No token anywhere.
- Check: `GET https://api.github.com/repos/{owner}/{repo}/releases/latest` over HTTPS, no auth. Read `tag_name` ("vX.Y.Z"), `body`, and assets. Need one `.apk` and one `.apk.sha256`, otherwise treat as no valid update. Ignore drafts and prereleases.
- Compare with the installed version (`package_info_plus`) using real semver (1.0.10 > 1.0.9). Ignore malformed tags. Never downgrade.
- Triggers: once per 24 h at app launch (persist `last_check`), and a manual "Check for updates" button. Auto-check failures are silent. Manual checks show a clear message.
- Dialog: current vs new version, release notes, "Update now", "Later", "Skip this version".
- Download only after "Update now", into the cache dir, with progress and cancel. Allow only github.com and GitHub's release asset hosts over HTTPS.
- Verify SHA-256 against the `.sha256` asset. Mismatch or missing: delete the file and abort. Never install an unverified file.
- Install through Android's system installer with a FileProvider and `REQUEST_INSTALL_PACKAGES`. If "Install unknown apps" is not granted, explain and deep-link to that settings page. Tell the user Android will show its own confirmation. Android cannot install silently.
- Offer a backup export before installing. Delete the downloaded APK after the attempt and on next launch.
- Updates never touch app data. Schema changes need versioned migrations with tests, and backup import must keep accepting older versions.

## 9. Installer and release workflow

- Build: `flutter build apk --release`. Files: `worship-setlist-vX.Y.Z.apk` and `worship-setlist-vX.Y.Z.apk.sha256` (hash plus filename).
- `applicationId` is a placeholder `com.worship.setlist`; the user may change it before the first build only. After the first install it is fixed forever.
- ONE release keystore, referenced by `android/key.properties`. Both are gitignored and NEVER committed. Release builds FAIL if the keystore is missing (no debug-signing fallback). Never print passwords. Document keystore setup in AGENTS.md with a warning to back up the keystore and passwords offline. If lost, installed copies cannot be updated, and an uninstall wipes local data unless a backup was exported.
- Version format `MAJOR.MINOR.PATCH+BUILD` in `pubspec.yaml`. BUILD is the versionCode and strictly increases.
- Bump ONLY when the user says "update the installer", "release", or "new version". Default is a PATCH bump (unless minor or major is requested) and BUILD+1. Then: update `pubspec.yaml`, add a plain-language `CHANGELOG.md` entry, run tests, build the signed APK, generate the `.sha256`, put outputs in `releases/` (gitignored), and print the exact `gh release create vX.Y.Z <apk> <sha256> --title ... --notes ...` command plus manual upload steps as a fallback. The tag equals the pubspec version with a leading `v`.
- Never push, tag, or publish unless the user explicitly says so. Provide `scripts/release.ps1` and `scripts/release.sh`.

## 10. Tests (no real network; mock HTTP)

- URL validation: allowed hosts, non-HTTPS rejected, non-`/tab/` path rejected, normalization, duplicate detection.
- Playlist logic: add, remove, move (up, down, to ends), position renormalization, duplicate playlist, next/previous bounds, duplicate song entries, resume position.
- Update: semver ordering, malformed tags, no downgrade, API parsing (valid, missing apk, missing sha256, draft/prerelease), checksum pass/fail deletes file, host allowlist, 24 h throttle, skipped version, offline/403/404 handled without a crash.
- Backup: export then import round-trips identical data; older `schema_version` still imports.
- Migration tests for any schema change.

## 11. Open assumptions (change here if wrong)

- Internet is reliable during the service. [user confirmed]
- No UG Pro account, so PDF download is dropped from v1. [user confirmed]
- Transpose uses UG's own page control. Whether it works on a free account is UNVERIFIED; test early. If it does not, add in-app transpose in a later version, which needs extracted text and is a larger change.
- A song may appear twice in one playlist. [assumption]
- UG may show ads, login prompts, or "open in app" banners inside the WebView, and may change or block this at any time. [assumption]
- Storing only links and the user's own notes is intended to avoid storing UG content. The user is responsible for how they use UG under UG's Terms of Service.
- Repo name and applicationId are placeholders. [placeholder]

## 12. Reviewer checklist

- [ ] No UG content stored, cached by custom code, parsed, or scraped.
- [ ] WebView navigation restricted to the two UG hosts. No JS channels. No injected JS. File access disabled.
- [ ] Network permission limited to INTERNET and REQUEST_INSTALL_PACKAGES. No secrets, tokens, or keys in the repo.
- [ ] Domain layer has no Flutter imports and has tests.
- [ ] Playlist positions stay contiguous after every operation.
- [ ] Destructive actions have confirmation. Service mode exit has confirmation.
- [ ] Update install is checksum-verified. Update dialogs never appear in Service mode.
- [ ] Keystore and key.properties are gitignored. Release build fails without them.
- [ ] Version is bumped only on the trigger phrases. Nothing is published automatically.
- [ ] Backup includes every table and a schema version.

## 13. Delivery order

1. Project setup, DB, domain logic (URL validation, playlist ordering) + tests. Create AGENTS.md and CLAUDE.md.
2. Songs library + "Browse UG" and "Paste link".
3. Playlists (create, add, reorder, duplicate).
4. Service mode.
5. Backup/restore.
6. Update feature, installer, release scripts, keystore docs.

Stop after each step for manual testing. Do not start a step before the previous one passes tests.
