#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in
  run|--verify|verify|--debug|debug|--logs|logs|--telemetry|telemetry|--release) ;;
  *) echo "usage: $0 [run|--verify|--debug|--logs|--telemetry|--release]" >&2; exit 2 ;;
esac
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="LocalMarkdown"
BUNDLE_ID="local.jojo.LocalMarkdown"
APP_BUNDLE="$ROOT_DIR/.build/package/debug/$APP_NAME.app"
BUILD_OPTIONS=()
if [[ "$MODE" == "--release" ]]; then
  APP_BUNDLE="$ROOT_DIR/.build/package/release/$APP_NAME.app"
  BUILD_OPTIONS=(-c release --arch arm64)
fi
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"

# Ask the app to quit normally, allowing its unsaved-document prompt to run.
if [[ "$MODE" != "--release" ]] && pgrep -x "$APP_NAME" >/dev/null; then
  osascript -e 'tell application id "local.jojo.LocalMarkdown" to quit'
  # App termination is asynchronous; give normal shutdown a short grace period.
  for attempt in {1..20}; do
    if ! pgrep -x "$APP_NAME" >/dev/null; then break; fi
    sleep 0.1
  done
  if pgrep -x "$APP_NAME" >/dev/null; then
    echo "请先保存并关闭 LocalMarkdown，再重新运行。" >&2
    exit 1
  fi
fi

swift build --disable-sandbox --cache-path "$ROOT_DIR/.build/cache" ${BUILD_OPTIONS[@]+"${BUILD_OPTIONS[@]}"}
BUILD_DIR="$(swift build --disable-sandbox --cache-path "$ROOT_DIR/.build/cache" ${BUILD_OPTIONS[@]+"${BUILD_OPTIONS[@]}"} --show-bin-path)"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
rsync -a --delete "$ROOT_DIR/Sources/LocalMarkdown/Resources/Editor/" "$APP_BUNDLE/Contents/Resources/Editor/"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/packaging/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [[ "$MODE" == "--release" && -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP_BUNDLE"
else
  codesign --force --sign - "$APP_BUNDLE"
fi
"$ROOT_DIR/script/verify_bundle.sh" "$APP_BUNDLE"

case "$MODE" in
  --release)
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
    ARCHIVE="$ROOT_DIR/dist/LocalMarkdown-$VERSION-macOS-arm64-local.zip"
    if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
      ARCHIVE="$ROOT_DIR/dist/LocalMarkdown-$VERSION-macOS-arm64-unnotarized.zip"
    fi
    ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"
    (cd "$ROOT_DIR/dist" && shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256")
    echo "安装包已生成（尚未公证）：$ARCHIVE"
    "$ROOT_DIR/script/create_dmg.sh" "$APP_BUNDLE"
    ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --verify|verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "LocalMarkdown 已启动：$APP_BUNDLE"
    ;;
  --debug|debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs|logs)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "LocalMarkdown"'
    ;;
  --telemetry|telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "local.jojo.LocalMarkdown"'
    ;;
  *) echo "usage: $0 [run|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
