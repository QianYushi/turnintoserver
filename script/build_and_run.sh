#!/usr/bin/env bash
set -euo pipefail

APP_NAME="turnintoserver"
PROJECT_NAME="turnintoserver.xcodeproj"
SCHEME_NAME="turnintoserver"
BUNDLE_ID="com.qianyushi.turnintoserver"
TEAM_ID="G79WZ47SUC"
DEVELOPER_ID_IDENTITY="Developer ID Application: Yushi Qian ($TEAM_ID)"
MODE="${1:-run}"
CONFIGURATION="Debug"
EXTRA_BUILD_SETTINGS=()

case "$MODE" in
  --release|release|--release-run|release-run|--release-verify|release-verify)
    CONFIGURATION="Release"
    EXTRA_BUILD_SETTINGS=(
      "CODE_SIGN_STYLE=Manual"
      "CODE_SIGN_IDENTITY=$DEVELOPER_ID_IDENTITY"
      "DEVELOPMENT_TEAM=$TEAM_ID"
      "ENABLE_HARDENED_RUNTIME=YES"
      "PROVISIONING_PROFILE_SPECIFIER="
    )
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="$HOME/Library/Developer/Xcode/DerivedData/turnintoserver-build"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
ROOT_APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"
ROOT_APP_BINARY="$ROOT_APP_BUNDLE/Contents/MacOS/$APP_NAME"

cd "$ROOT_DIR"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  CURRENT_DEVELOPER_DIR="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
  if [[ "$CURRENT_DEVELOPER_DIR" == "/Library/Developer/CommandLineTools" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -f "[/]turnintoserver.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
pkill -f "$APP_BINARY" >/dev/null 2>&1 || true

XCODEBUILD_ARGS=(
  -project "$PROJECT_NAME"
  -scheme "$SCHEME_NAME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA_DIR"
)

if [[ ${#EXTRA_BUILD_SETTINGS[@]} -gt 0 ]]; then
  XCODEBUILD_ARGS+=("${EXTRA_BUILD_SETTINGS[@]}")
fi

xcodebuild "${XCODEBUILD_ARGS[@]}" build

/bin/rm -rf "$ROOT_APP_BUNDLE"
/usr/bin/ditto --norsrc --noextattr "$APP_BUNDLE" "$ROOT_APP_BUNDLE"
/usr/bin/SetFile -a b "$ROOT_APP_BUNDLE" 2>/dev/null || true
/usr/bin/xattr -cr "$ROOT_APP_BUNDLE"
if [[ "$CONFIGURATION" == "Release" ]]; then
  for attempt in 1 2 3; do
    /usr/bin/SetFile -a b "$ROOT_APP_BUNDLE" 2>/dev/null || true
    /usr/bin/xattr -cr "$ROOT_APP_BUNDLE"
    /usr/bin/xattr -d com.apple.FinderInfo "$ROOT_APP_BUNDLE" 2>/dev/null || true
    /usr/bin/xattr -d "com.apple.fileprovider.fpfs#P" "$ROOT_APP_BUNDLE" 2>/dev/null || true

    if /usr/bin/codesign \
      --force \
      --options runtime \
      --timestamp \
      --sign "$DEVELOPER_ID_IDENTITY" \
      "$ROOT_APP_BUNDLE"; then
      break
    fi

    if [[ "$attempt" == "3" ]]; then
      exit 1
    fi

    sleep 2
  done
fi
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f -R -trusted "$ROOT_APP_BUNDLE" >/dev/null 2>&1 || true
fi

open_app() {
  /usr/bin/open -n "$ROOT_APP_BUNDLE"
}

case "$MODE" in
  run|--release|release|--release-run|release-run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$ROOT_APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify|--release-verify|release-verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null || pgrep -f "$ROOT_APP_BINARY" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--release|--release-run|--release-verify]" >&2
    exit 2
    ;;
esac
