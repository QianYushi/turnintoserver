#!/usr/bin/env bash
set -euo pipefail

APP_NAME="turnintoserver"
PROFILE_NAME="${NOTARY_PROFILE:-turnintoserver-notary}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="$ROOT_DIR/$APP_NAME.dmg"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  CURRENT_DEVELOPER_DIR="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
  if [[ "$CURRENT_DEVELOPER_DIR" == "/Library/Developer/CommandLineTools" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "missing dmg: $DMG_PATH" >&2
  exit 1
fi

/usr/bin/hdiutil verify "$DMG_PATH" -quiet
/usr/bin/codesign --verify --verbose=2 "$DMG_PATH"

/usr/bin/xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$PROFILE_NAME" \
  --wait

/usr/bin/xcrun stapler staple "$DMG_PATH"
/usr/bin/xcrun stapler validate "$DMG_PATH"
/usr/sbin/spctl -a -vvv --type open --context context:primary-signature "$DMG_PATH"
