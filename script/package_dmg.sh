#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="^V"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
DMG_PATH="${CTRLV_DMG_PATH:-$ROOT_DIR/dist/$APP_NAME.dmg}"

if [[ "${1:-}" != "--skip-build" || ! -d "$APP_BUNDLE" ]]; then
  "$ROOT_DIR/script/build_and_run.sh" --build >/dev/null
fi

STAGING_DIR="$(mktemp -d "/tmp/ctrlv-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto --noextattr --noqtn "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
codesign --verify --deep --strict "$STAGING_DIR/$APP_NAME.app"

mkdir -p "$(dirname "$DMG_PATH")"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

SIGNING_IDENTITY="${CTRLV_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Developer ID Application:|"Apple Development:/ && !/CSSMERR/ { print $2; exit }')"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
fi
xattr -cr "$DMG_PATH"
codesign --force --sign "$SIGNING_IDENTITY" --identifier app.ctrlv.clipboard.dmg "$DMG_PATH"
echo "$DMG_PATH"
