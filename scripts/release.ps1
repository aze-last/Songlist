<#
.SYNOPSIS
  Automates the release build and SHA-256 checksum generation for Worship Setlist.
.DESCRIPTION
  Under spec.md Section 9 & 10:
  1. Verifies android/key.properties exists (release signing protection).
  2. Extracts version from pubspec.yaml.
  3. Executes `flutter build apk --release`.
  4. Generates SHA-256 checksum file matching standard format: `<hash>  <apk_name>`.
  5. Moves artifacts to releases/ directory.
  6. Prints GitHub CLI release command.
#>

$ErrorActionPreference = "Stop"

# 1. Verify release keystore properties
$KeyProps = "android\key.properties"
if (-not (Test-Path $KeyProps)) {
    Write-Error @"
[ERROR] Missing android\key.properties!
Release builds require a valid release keystore configuration to ensure ongoing app updates.
See AGENTS.md Section 3 for setup instructions:
  keytool -genkey -v -keystore release.keystore -alias worship-key -keyalg RSA -keysize 2048 -validity 10000
"@
    exit 1
}

# 2. Extract version from pubspec.yaml
$Pubspec = Get-Content "pubspec.yaml" -Raw
if ($Pubspec -match "version:\s*([0-9]+\.[0-9]+\.[0-9]+)(\+[0-9]+)?") {
    $Version = $Matches[1]
    $Tag = "v$Version"
} else {
    Write-Error "[ERROR] Could not parse semver from pubspec.yaml!"
    exit 1
}

Write-Host "==> Preparing Worship Setlist Release $Tag" -ForegroundColor Cyan

# 3. Clean and build release APK
Write-Host "==> Running flutter build apk --release..." -ForegroundColor Cyan
flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    Write-Error "[ERROR] flutter build apk --release failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

$BuiltApk = "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $BuiltApk)) {
    Write-Error "[ERROR] Built APK not found at $BuiltApk!"
    exit 1
}

# 4. Prepare releases directory
$ReleasesDir = "releases"
if (-not (Test-Path $ReleasesDir)) {
    New-Item -ItemType Directory -Path $ReleasesDir | Out-Null
}

$ReleaseApkName = "worship-setlist-$Tag.apk"
$TargetApk = Join-Path $ReleasesDir $ReleaseApkName
$TargetSha = Join-Path $ReleasesDir "$ReleaseApkName.sha256"

Copy-Item -Path $BuiltApk -Destination $TargetApk -Force

# 5. Compute SHA-256
$Hash = (Get-FileHash -Path $TargetApk -Algorithm SHA256).Hash.ToLower()
$ShaContent = "$Hash  $ReleaseApkName"
[System.IO.File]::WriteAllText($TargetSha, "$ShaContent`n", [System.Text.Encoding]::UTF8)

Write-Host "`n[SUCCESS] Release artifacts generated in $ReleasesDir/:" -ForegroundColor Green
Write-Host "  APK:    $TargetApk" -ForegroundColor Green
Write-Host "  SHA256: $TargetSha ($Hash)" -ForegroundColor Green
Write-Host "`n==> To publish to GitHub Releases via GitHub CLI, run:" -ForegroundColor Yellow
Write-Host "  gh release create $Tag $TargetApk $TargetSha --title `"Release $Tag`" --notes `"Release $Tag notes.`"" -ForegroundColor White
