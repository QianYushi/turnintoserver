#!/usr/bin/env bash
set -euo pipefail

APP_NAME="turnintoserver"
VOL_NAME="turnintoserver"
TEAM_ID="G79WZ47SUC"
DEVELOPER_ID_IDENTITY="Developer ID Application: Yushi Qian ($TEAM_ID)"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-$ROOT_DIR/$APP_NAME.app}"
CLEAN_APP_BUNDLE=""
DMG_PATH="${DMG_PATH:-$ROOT_DIR/$APP_NAME.dmg}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-$ROOT_DIR/$APP_NAME/$APP_NAME.entitlements}"
STAGING_DIR=""
RW_DMG=""
DEVICE=""

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    /usr/bin/hdiutil detach "$DEVICE" -quiet >/dev/null 2>&1 || true
  fi

  if [[ -n "$STAGING_DIR" ]]; then
    /bin/rm -rf "$STAGING_DIR"
  fi

  if [[ -n "$RW_DMG" ]]; then
    /bin/rm -f "$RW_DMG"
  fi
}
trap cleanup EXIT

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
STAGING_DIR="$(/usr/bin/mktemp -d "$TMPDIR/turnintoserver-dmg.XXXXXX")"
CLEAN_APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"

clean_app_metadata() {
  /usr/bin/SetFile -a b "$APP_BUNDLE" 2>/dev/null || true
  /usr/bin/xattr -cr "$APP_BUNDLE"
  /usr/bin/xattr -d com.apple.FinderInfo "$APP_BUNDLE" 2>/dev/null || true
  /usr/bin/xattr -d "com.apple.fileprovider.fpfs#P" "$APP_BUNDLE" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.macl "$APP_BUNDLE" 2>/dev/null || true
}

for attempt in 1 2 3; do
  clean_app_metadata
  /bin/rm -rf "$CLEAN_APP_BUNDLE"
  /usr/bin/ditto --norsrc --noextattr "$APP_BUNDLE" "$CLEAN_APP_BUNDLE"
  /usr/bin/xattr -cr "$CLEAN_APP_BUNDLE"
  CODESIGN_ARGS=(
    --force
    --options runtime
    --timestamp
    --sign "$DEVELOPER_ID_IDENTITY"
  )
  if [[ -f "$ENTITLEMENTS_PATH" ]]; then
    CODESIGN_ARGS+=(--entitlements "$ENTITLEMENTS_PATH")
  fi
  /usr/bin/codesign "${CODESIGN_ARGS[@]}" "$CLEAN_APP_BUNDLE"

  if /usr/bin/codesign --verify --deep --strict --verbose=2 "$CLEAN_APP_BUNDLE"; then
    break
  fi

  if [[ "$attempt" == "3" ]]; then
    exit 1
  fi

  sleep 1
done

RW_DMG="$STAGING_DIR/$APP_NAME-rw.dmg"
MOUNT_POINT="/Volumes/$VOL_NAME"
BACKGROUND_DIR="$STAGING_DIR/background"
BACKGROUND_IMAGE="$BACKGROUND_DIR/background.png"

/bin/mkdir -p "$BACKGROUND_DIR"

/usr/bin/swift - "$BACKGROUND_IMAGE" <<'SWIFT'
import AppKit

let outputPath = CommandLine.arguments[1]
let canvas = NSSize(width: 620, height: 380)
let image = NSImage(size: canvas)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor, centered: Bool = true) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = centered ? .center : .left
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let size = attributed.size()
    let rect = NSRect(
        x: centered ? point.x - size.width / 2 : point.x,
        y: point.y,
        width: size.width + 4,
        height: size.height + 2
    )
    attributed.draw(in: rect)
}

image.lockFocus()

color(247, 249, 252).setFill()
NSRect(origin: .zero, size: canvas).fill()

let topWash = NSGradient(colors: [
    color(255, 255, 255, 0.96),
    color(238, 243, 249, 0.86)
])
topWash?.draw(in: NSRect(x: 0, y: 205, width: canvas.width, height: 175), angle: 90)

for rect in [
    NSRect(x: 65, y: 86, width: 170, height: 190),
    NSRect(x: 385, y: 86, width: 170, height: 190)
] {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(25, 35, 55, 0.10)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()

    color(255, 255, 255, 0.92).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28).fill()
    NSGraphicsContext.restoreGraphicsState()
}

drawText(
    "turnintoserver",
    at: NSPoint(x: canvas.width / 2, y: 318),
    font: NSFont.systemFont(ofSize: 25, weight: .semibold),
    color: color(28, 34, 46)
)
drawText(
    "拖到应用程序 / Drag to Applications",
    at: NSPoint(x: canvas.width / 2, y: 291),
    font: NSFont.systemFont(ofSize: 13, weight: .regular),
    color: color(92, 101, 116)
)

let arrow = NSBezierPath()
arrow.lineWidth = 8
arrow.lineCapStyle = .round
arrow.move(to: NSPoint(x: 264, y: 178))
arrow.line(to: NSPoint(x: 356, y: 178))
color(103, 116, 139, 0.72).setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 356, y: 178))
arrowHead.line(to: NSPoint(x: 333, y: 199))
arrowHead.move(to: NSPoint(x: 356, y: 178))
arrowHead.line(to: NSPoint(x: 333, y: 157))
arrowHead.lineWidth = 8
arrowHead.lineCapStyle = .round
color(103, 116, 139, 0.72).setStroke()
arrowHead.stroke()

drawText(
    "install",
    at: NSPoint(x: canvas.width / 2, y: 134),
    font: NSFont.systemFont(ofSize: 12, weight: .medium),
    color: color(116, 126, 145)
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outputPath))
SWIFT

/usr/bin/hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
/bin/rm -f "$DMG_PATH"
/usr/bin/hdiutil create "$RW_DMG" -volname "$VOL_NAME" -size 64m -fs HFS+ -ov -quiet
DEVICE="$(/usr/bin/hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen | /usr/bin/awk '/Apple_HFS/ {print $1; exit}')"

if [[ -z "$DEVICE" || ! -d "$MOUNT_POINT" ]]; then
  echo "failed to mount temporary dmg" >&2
  exit 1
fi

/usr/bin/ditto --norsrc --noextattr "$CLEAN_APP_BUNDLE" "$MOUNT_POINT/$APP_NAME.app"
/bin/ln -s /Applications "$MOUNT_POINT/Applications"
/bin/mkdir -p "$MOUNT_POINT/.background"
/bin/cp "$BACKGROUND_IMAGE" "$MOUNT_POINT/.background/background.png"
/bin/cp "$CLEAN_APP_BUNDLE/Contents/Resources/AppIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
/usr/bin/SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
/usr/bin/SetFile -a V "$MOUNT_POINT/.background" "$MOUNT_POINT/.VolumeIcon.icns" 2>/dev/null || true

/usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 740, 500}
    set theOptions to icon view options of container window
    set arrangement of theOptions to not arranged
    set icon size of theOptions to 112
    set background picture of theOptions to file ".background:background.png"
    set position of item "$APP_NAME.app" to {150, 208}
    set position of item "Applications" to {470, 208}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

/bin/sync
/usr/bin/hdiutil detach "$DEVICE" -quiet
DEVICE=""

/usr/bin/hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" -quiet
/usr/bin/xattr -cr "$DMG_PATH"
/usr/bin/codesign --force --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$DMG_PATH"
/usr/bin/hdiutil verify "$DMG_PATH" -quiet
/usr/bin/codesign --verify --verbose=2 "$DMG_PATH"

echo "$DMG_PATH"
