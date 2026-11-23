# AGENTS.md — Development & Architecture Guidelines

This repository is governed by the specifications in [spec.md](spec.md) and the operational rules in [.agents/rules.md](.agents/rules.md). All AI agents and developers must strictly adhere to these guidelines.

---

## 1. Architectural Boundaries

- **`lib/domain/`**: Pure Dart only. Zero Flutter or UI imports (`package:flutter/*`). Contains URL validation, playlist ordering logic, and semver comparison. Fully unit-tested.
- **`lib/data/`**: Drift SQLite database, DAOs, repositories, and platform services.
- **`lib/presentation/`**: Flutter widgets, screens, and Riverpod state providers.
- **`lib/config/update_config.dart`**: Remote update configuration (`githubOwner`, `githubRepo`).

---

## 2. Ultimate Guitar (UG) Compliance & Security

- **NO Stored/Cached Content**: Do NOT store, copy, cache, parse, extract, or screenshot UG content (no lyrics, chords, PDFs, or HTML).
- **Storage Scope**: The app stores ONLY song title, UG URL, the user's short notes, playlists, and settings.
- **WebView Isolation**:
  - Navigation allowed ONLY to `tabs.ultimate-guitar.com` and `www.ultimate-guitar.com` over HTTPS.
  - All other URLs are blocked (prompt to open in system browser).
  - No JavaScript channels (page cannot call into app).
  - No injected JavaScript for scraping or content manipulation.
  - Disable file access and content access in WebView.
- **Zero Secrets**: No API keys, tokens, or passwords anywhere in the repository.

---

## 3. Release Keystore Setup & Warning

> **CRITICAL WARNING — BACK UP OFFLINE:**
> Android app updates require signing with the EXACT same release keystore. If the keystore or passwords are lost, installed copies CANNOT be updated, and an uninstall wipes local SQLite data unless a backup was exported. Back up the release keystore and passwords offline in a secure password manager.

### Keystore Configuration
1. Generate keystore (run locally by human developer, never committed):
   ```bash
   keytool -genkey -v -keystore release.keystore -alias worship-key -keyalg RSA -keysize 2048 -validity 10000
   ```
2. Place `key.properties` in `android/key.properties`:
   ```properties
   storePassword=<PASSWORD>
   keyPassword=<PASSWORD>
   keyAlias=worship-key
   storeFile=../release.keystore
   ```
3. `android/key.properties` and `*.keystore` / `*.jks` are gitignored.
4. Release builds must fail if `android/key.properties` is missing (no debug-signing fallback).

---

## 4. Engineering Discipline & Quality Gate

- All commands should be prefixed with `rtk` (e.g., `rtk flutter test`, `rtk git status`).
- Mandatory TDD: **RED -> GREEN -> IMPROVE**.
- Deterministic verification: Run [.agents/team/diff-scan.ps1](.agents/team/diff-scan.ps1) (Windows) or `bash .agents/team/diff-scan.sh` before completing any task.
