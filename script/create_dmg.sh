#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:?usage: create_dmg.sh /path/to/LocalMarkdown.app}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp/}localmarkdown-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
DMG="$ROOT_DIR/dist/LocalMarkdown-$VERSION-macOS-arm64.dmg"
ditto "$APP_BUNDLE" "$STAGING_DIR/LocalMarkdown.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$ROOT_DIR/packaging/安装说明.txt" "$STAGING_DIR/安装说明.txt"
hdiutil create -volname "LocalMarkdown $VERSION" -srcfolder "$STAGING_DIR" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
(cd "$ROOT_DIR/dist" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "DMG 已生成：$DMG"
