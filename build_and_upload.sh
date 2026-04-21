#!/bin/zsh
set -euo pipefail

# ─── How Pranked My House: Build & Upload to App Store Connect ───
# Usage: ./build_and_upload.sh
#
# Requirements:
#   - Flutter SDK on PATH
#   - fastlane installed (brew install fastlane)
#   - App-specific password set via FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD
#     environment variable, or you will be prompted during upload.
#
# To generate an app-specific password:
#   https://account.apple.com → Sign-In and Security → App-Specific Passwords

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# ─── Load environment variables and export for child processes ───
if [[ -f .env ]]; then
  set -a  # auto-export all variables
  source .env
  set +a
else
  echo "⚠ No .env file found. FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD must be set."
fi

echo "══════════════════════════════════════════════════"
echo "  How Pranked My House — Build & Upload"
echo "══════════════════════════════════════════════════"

# ─── Extract version info from pubspec.yaml ───
VERSION_LINE=$(grep '^version:' pubspec.yaml)
VERSION=$(echo "$VERSION_LINE" | sed 's/version: *//' | cut -d'+' -f1)
BUILD_NUMBER=$(echo "$VERSION_LINE" | sed 's/version: *//' | cut -d'+' -f2)
echo "  Version: $VERSION  Build: $BUILD_NUMBER"
echo ""

# ─── Step 1: Clean previous build artifacts ───
echo "▸ Cleaning previous build..."
flutter clean
flutter pub get

# ─── Step 2: Build the release IPA ───
echo ""
echo "▸ Building release IPA..."
flutter build ipa --release

echo ""
echo "✓ Archive built successfully"
echo ""

# ─── Step 3: Export and upload via fastlane ───
echo "▸ Exporting IPA and uploading to App Store Connect..."
cd ios
fastlane release

echo ""
echo "══════════════════════════════════════════════════"
echo "  ✓ Build $VERSION ($BUILD_NUMBER) uploaded!"
echo "══════════════════════════════════════════════════"
echo ""
echo "  Check App Store Connect for processing status:"
echo "  https://appstoreconnect.apple.com"
echo ""
