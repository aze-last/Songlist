#!/usr/bin/env bash
set -euo pipefail

# 1. Verify release keystore properties
KEY_PROPS="android/key.properties"
if [ ! -f "$KEY_PROPS" ]; then
    echo "[ERROR] Missing android/key.properties!" >&2
    echo "Release builds require a valid release keystore configuration." >&2
    echo "See AGENTS.md Section 3 for setup instructions." >&2
    exit 1
fi

# 2. Extract version from pubspec.yaml
VERSION=$(grep -E '^version:' pubspec.yaml | head -n 1 | sed -E 's/version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
if [ -z "$VERSION" ]; then
    echo "[ERROR] Could not parse semver from pubspec.yaml!" >&2
    exit 1
fi
TAG="v$VERSION"

echo "==> Preparing Worship Setlist Release $TAG"

# 3. Build release APK
echo "==> Running flutter build apk --release..."
flutter build apk --release

BUILT_APK="build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$BUILT_APK" ]; then
    echo "[ERROR] Built APK not found at $BUILT_APK!" >&2
    exit 1
fi

# 4. Prepare releases directory
mkdir -p releases
RELEASE_APK_NAME="worship-setlist-$TAG.apk"
TARGET_APK="releases/$RELEASE_APK_NAME"
TARGET_SHA="releases/$RELEASE_APK_NAME.sha256"

cp "$BUILT_APK" "$TARGET_APK"

# 5. Compute SHA-256
if command -v sha256sum >/dev/null 2>&1; then
    (cd releases && sha256sum "$RELEASE_APK_NAME" > "$RELEASE_APK_NAME.sha256")
elif command -v shasum >/dev/null 2>&1; then
    (cd releases && shasum -a 256 "$RELEASE_APK_NAME" > "$RELEASE_APK_NAME.sha256")
else
    echo "[ERROR] Neither sha256sum nor shasum is available to compute checksum." >&2
    exit 1
fi

echo ""
echo "[SUCCESS] Release artifacts generated in releases/:"
echo "  APK:    $TARGET_APK"
echo "  SHA256: $TARGET_SHA"
echo ""
echo "==> To publish to GitHub Releases via GitHub CLI, run:"
echo "  gh release create $TAG $TARGET_APK $TARGET_SHA --title \"Release $TAG\" --notes \"Release $TAG notes.\""
