#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_NAME="^V"
BIN_NAME="ctrlv"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME.dmg"
case "$MODE" in
  run|--verify|--debug|--logs|--telemetry|--build|--dmg) ;;
  *) echo "usage: $0 [--build|--dmg|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
if [[ "$MODE" != "--build" && "$MODE" != "--dmg" ]]; then pkill -x "$BIN_NAME" >/dev/null 2>&1 || true; fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/ctrlv-clang-module-cache}"
ARCH_FLAGS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCH_FLAGS[@]}" --disable-sandbox -Xswiftc -module-cache-path -Xswiftc "$CLANG_MODULE_CACHE_PATH"
BUILD_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path --disable-sandbox)"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$BIN_NAME" "$APP_BUNDLE/Contents/MacOS/$BIN_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
xattr -cr "$APP_BUNDLE"
# A default ad-hoc signature is tied to the binary's hash, invalidating the
# Accessibility grant after each rebuild. Prefer a stable signing identity.
SIGNING_IDENTITY="${CTRLV_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Developer ID Application:|"Apple Development:/ && !/CSSMERR/ { print $2; exit }')"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
  echo "No signing identity found. Using ad-hoc signing (other Macs will require removing quarantine or clicking Open Anyway in Privacy & Security)." >&2
fi
codesign --force --deep --sign "$SIGNING_IDENTITY" --identifier app.ctrlv.clipboard "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
case "$MODE" in
  --build) echo "$APP_BUNDLE" ;;
  --dmg) "$ROOT_DIR/script/package_dmg.sh" --skip-build ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$BIN_NAME" ;;
  --logs|--telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "ctrlv"'
    ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 1
    pgrep -x "$BIN_NAME" >/dev/null
    echo "$APP_NAME built and running."
    ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
esac
