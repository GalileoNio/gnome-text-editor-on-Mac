#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$ROOT_DIR"
BUILD_DIR="$SRC_DIR/build-macos"
PREFIX="$SRC_DIR/_install"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Text Editor"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
BUNDLE_ID="org.gnome.TextEditor"
EXECUTABLE="gnome-text-editor"
BREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
LOG_FILE="$DIST_DIR/gnome-text-editor-launch.log"
ADWAITA_ICON_DIR="$BREW_PREFIX/share/icons/Adwaita"

verify=false
launch=true

for arg in "$@"; do
  case "$arg" in
    --verify)
      verify=true
      ;;
    --no-launch)
      launch=false
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

export PATH="$BREW_PREFIX/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

if [[ ! -f "$SRC_DIR/meson.build" ]]; then
  echo "Missing GNOME Text Editor source tree: $SRC_DIR" >&2
  exit 1
fi

if [[ "$launch" == true ]]; then
  pkill -x "$EXECUTABLE" 2>/dev/null || true
fi

pushd "$SRC_DIR" >/dev/null
if [[ ! -f "$BUILD_DIR/meson-private/build.dat" ]]; then
  meson setup "$BUILD_DIR" "$SRC_DIR" --prefix "$PREFIX"
else
  meson setup --reconfigure --prefix "$PREFIX" "$BUILD_DIR"
fi

meson compile -C "$BUILD_DIR"
meson install -C "$BUILD_DIR"
popd >/dev/null

if [[ -d "$APP_BUNDLE" ]]; then
  chmod -R u+w "$APP_BUNDLE" 2>/dev/null || true
  rm -rf "$APP_BUNDLE"
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$SRC_DIR/data/macos/org.gnome.TextEditor.icns" \
  "$APP_BUNDLE/Contents/Resources/org.gnome.TextEditor.icns"
mkdir -p "$APP_BUNDLE/Contents/Resources/_install"
cp -R "$PREFIX/." "$APP_BUNDLE/Contents/Resources/_install/"
if [[ -d "$ADWAITA_ICON_DIR" ]]; then
  mkdir -p "$APP_BUNDLE/Contents/Resources/_install/share/icons/Adwaita"
  cp -RL "$ADWAITA_ICON_DIR/." \
    "$APP_BUNDLE/Contents/Resources/_install/share/icons/Adwaita/"
else
  echo "Warning: missing Adwaita icon theme. Install it with: brew install adwaita-icon-theme" >&2
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>org.gnome.TextEditor.icns</string>
  <key>CFBundleShortVersionString</key>
  <string>51.beta</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

cc "$ROOT_DIR/script/macos_launcher.c" -o "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"
/usr/bin/touch "$APP_BUNDLE"

if [[ "$launch" == true ]]; then
  sleep 1
  /usr/bin/open -n "$APP_BUNDLE"

  if [[ "$verify" == true ]]; then
    found=false
    for _ in {1..40}; do
      if pgrep -x "$EXECUTABLE" >/dev/null 2>&1 ||
         pgrep -f "$PREFIX/bin/$EXECUTABLE" >/dev/null 2>&1; then
        found=true
        break
      fi
      sleep 0.25
    done

    if [[ "$found" != true ]]; then
      echo "$APP_NAME did not appear as a running process." >&2
      [[ -f "$LOG_FILE" ]] && tail -n 80 "$LOG_FILE" >&2
      exit 1
    fi

    for _ in {1..12}; do
      sleep 0.25
      if ! pgrep -x "$EXECUTABLE" >/dev/null 2>&1 &&
         ! pgrep -f "$PREFIX/bin/$EXECUTABLE" >/dev/null 2>&1; then
        echo "$APP_NAME launched, then exited during verification." >&2
        [[ -f "$LOG_FILE" ]] && tail -n 80 "$LOG_FILE" >&2
        exit 1
      fi
    done

    echo "$APP_NAME is running from $APP_BUNDLE"
    exit 0
  fi
fi

echo "Built app bundle: $APP_BUNDLE"
