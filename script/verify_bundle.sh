#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:?usage: verify_bundle.sh /path/to/LocalMarkdown.app}"
PLIST="$APP_BUNDLE/Contents/Info.plist"
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/LocalMarkdown"
plutil -lint "$PLIST"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")" == "14.0" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")" == "LocalMarkdown" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$PLIST")" == "APPL" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :UTImportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension:0' "$PLIST")" == "md" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :UTImportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension:1' "$PLIST")" == "markdown" ]]
test -x "$EXECUTABLE"
test -s "$APP_BUNDLE/Contents/Resources/Editor/index.html"
test -s "$APP_BUNDLE/Contents/Resources/Editor/THIRD-PARTY-NOTICES.txt"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
ARCHITECTURES="$(lipo -archs "$EXECUTABLE")"
[[ "$ARCHITECTURES" == "arm64" ]]
MINIMUM_OS="$(xcrun vtool -show-build "$EXECUTABLE" | awk '/minos/ {print $2}')"
[[ "$MINIMUM_OS" == "14.0" ]]
echo "Bundle 验证通过：${ARCHITECTURES}，最低 macOS ${MINIMUM_OS}；签名完整性通过不代表已通过 Apple 公证。"
