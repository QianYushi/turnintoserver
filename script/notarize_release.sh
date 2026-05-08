#!/usr/bin/env bash
set -euo pipefail

APP_NAME="turnintoserver"
PROFILE_NAME="${NOTARY_PROFILE:-turnintoserver-notary}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"
SUBMISSION_ZIP_PATH="$ROOT_DIR/$APP_NAME-notary.zip"
DISTRIBUTION_ZIP_PATH="$ROOT_DIR/$APP_NAME-notarized.zip"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  CURRENT_DEVELOPER_DIR="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
  if [[ "$CURRENT_DEVELOPER_DIR" == "/Library/Developer/CommandLineTools" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "missing app bundle: $APP_BUNDLE" >&2
  exit 1
fi

cd "$ROOT_DIR"

clean_app_metadata() {
  /usr/bin/SetFile -a b "$APP_BUNDLE" 2>/dev/null || true
  /usr/bin/xattr -cr "$APP_BUNDLE"
  /usr/bin/xattr -d com.apple.FinderInfo "$APP_BUNDLE" 2>/dev/null || true
  /usr/bin/xattr -d "com.apple.fileprovider.fpfs#P" "$APP_BUNDLE" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.macl "$APP_BUNDLE" 2>/dev/null || true
}

for attempt in 1 2 3; do
  clean_app_metadata

  if /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"; then
    break
  fi

  if [[ "$attempt" == "3" ]]; then
    exit 1
  fi

  sleep 1
done

/bin/rm -f "$SUBMISSION_ZIP_PATH" "$DISTRIBUTION_ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$SUBMISSION_ZIP_PATH"

/usr/bin/xcrun notarytool submit "$SUBMISSION_ZIP_PATH" \
  --keychain-profile "$PROFILE_NAME" \
  --wait

/usr/bin/xcrun stapler staple "$APP_BUNDLE"
/usr/bin/xcrun stapler validate "$APP_BUNDLE"
/usr/sbin/spctl -a -vvv --type exec "$APP_BUNDLE"

/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$DISTRIBUTION_ZIP_PATH"
