#!/usr/bin/env bash
# build_ipa_macos.sh — Build Scandium.ipa on macOS with Xcode's toolchain (no xtool).
#
# Compiles Sources/ with swiftc for arm64 iOS 15, assembles the .app bundle
# (Info.plist + assets/*.png), weak-links iOS 18+ frameworks, ad-hoc signs with
# entitlements.plist, and zips Payload/ into Scandium.ipa at the project root.
#
# Usage: ./scripts/build_ipa_macos.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Scandium"
BUNDLE_ID="com.meohunter.scandium"
MIN_IOS="15.0"
BUILD_DIR="${PROJECT_ROOT}/.build/ipa"
APP="${BUILD_DIR}/Payload/${APP_NAME}.app"
IPA="${PROJECT_ROOT}/${APP_NAME}.ipa"

cd "${PROJECT_ROOT}"
VERSION="$(git describe --tags --always 2>/dev/null || echo dev)"
# The version lives in Info.plist
SHORT_VERSION="$(plutil -extract CFBundleShortVersionString raw Info.plist)"

rm -rf "${BUILD_DIR}"
mkdir -p "${APP}"

echo "[1/5] Compiling ${APP_NAME} for arm64-apple-ios${MIN_IOS}..."
SOURCES=()
while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find Sources/Scandium -name '*.swift' -print0)
xcrun -sdk iphoneos swiftc \
    -target "arm64-apple-ios${MIN_IOS}" \
    -swift-version 5 \
    -O -whole-module-optimization \
    -parse-as-library \
    -module-name "${APP_NAME}" \
    "${SOURCES[@]}" \
    -o "${APP}/${APP_NAME}"

echo "[2/5] Assembling bundle..."
cp Info.plist "${APP}/Info.plist"
P="${APP}/Info.plist"
set_key() { plutil -replace "$1" "$2" "$3" "$P"; }
set_key CFBundleExecutable -string "${APP_NAME}"
set_key CFBundleIdentifier -string "${BUNDLE_ID}"
set_key CFBundleName -string "${APP_NAME}"
set_key CFBundlePackageType -string APPL
set_key CFBundleInfoDictionaryVersion -string 6.0
set_key CFBundleDevelopmentRegion -string en
set_key MinimumOSVersion -string "${MIN_IOS}"
set_key LSRequiresIPhoneOS -bool YES
plutil -replace CFBundleSupportedPlatforms -json '["iPhoneOS"]' "$P"
plutil -replace UIDeviceFamily -json '[1,2]' "$P"
plutil -replace UIRequiredDeviceCapabilities -json '["arm64"]' "$P"
plutil -replace UISupportedInterfaceOrientations -json '["UIInterfaceOrientationPortrait"]' "$P"
plutil -lint "$P" >/dev/null
cp assets/*.png "${APP}/"
printf 'APPL????' > "${APP}/PkgInfo"

echo "[3/5] Weak-linking iOS 18+ frameworks..."
python3 scripts/patch_macho_weak.py "${APP}/${APP_NAME}"

echo "[4/5] Ad-hoc signing with entitlements.plist..."
codesign --force --sign - --entitlements entitlements.plist --timestamp=none "${APP}"

echo "[5/5] Packaging ${IPA}..."
rm -f "${IPA}"
# -X: no extra file attributes (owner IDs, macOS metadata) in the archive
(cd "${BUILD_DIR}" && zip -qryX "${IPA}" Payload)

echo "Done (${VERSION}): ${IPA} ($(du -h "${IPA}" | cut -f1))"
