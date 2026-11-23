# CLAUDE.md — Agent Workspace Instructions

## Overview
Worship Setlist is a single-user portrait Android app built with Flutter, Riverpod, Drift (SQLite), and WebView. It stores songs as links to Ultimate Guitar (UG) pages and organizes them into weekly Sunday playlists.

- **Authoritative Specification**: [spec.md](spec.md)
- **Architecture & Keystore Rules**: [AGENTS.md](AGENTS.md)
- **Agent Governance & Gates**: [.agents/rules.md](.agents/rules.md)

## Common Commands (always prefix with `rtk`)
- Run tests: `rtk flutter test`
- Analyze code: `rtk flutter analyze`
- Format code: `rtk dart format .`
- Run pre-flight gate: `powershell -NoProfile -ExecutionPolicy Bypass -File .agents\team\diff-scan.ps1`
- Run code generation: `rtk dart run build_runner build --delete-conflicting-outputs`

## Key Invariants
1. `lib/domain/` is pure Dart with NO Flutter imports.
2. Never store, extract, parse, or cache chords/lyrics from Ultimate Guitar.
3. WebView navigation is strictly locked to `tabs.ultimate-guitar.com` and `www.ultimate-guitar.com` via HTTPS.
4. Songs are archived (`archived = true`), never hard-deleted.
5. Playlist item positions are 0-indexed and strictly contiguous (0..n-1).
