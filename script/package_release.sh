#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Text Editor"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ARTIFACT="$DIST_DIR/gnome-text-editor-macos-arm64-homebrew.dmg"
CHECKSUM="$ARTIFACT.sha256"
NOTES="$DIST_DIR/release-notes.md"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gnome-text-editor-dmg.XXXXXX")"

cleanup() {
  chmod -R u+w "$STAGE_DIR" 2>/dev/null || true
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

"$ROOT_DIR/script/build_and_run.sh" --no-launch

xattr -cr "$APP_BUNDLE" 2>/dev/null || true
xattr -c "$APP_BUNDLE" 2>/dev/null || true
codesign --force --deep --sign "$CODESIGN_IDENTITY" --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
ditto --norsrc --noextattr --noqtn --noacl --nopersistRootless \
  "$APP_BUNDLE" "$STAGE_DIR/$APP_NAME.app"
codesign --verify --deep --strict --verbose=2 "$STAGE_DIR/$APP_NAME.app"

cat > "$NOTES" <<'NOTES'
# GNOME Text Editor for macOS

Unofficial macOS arm64 build of GNOME Text Editor.

## Requirements

This package includes GNOME Text Editor resources inside the app bundle, but it
still links against the GTK stack installed by Homebrew:

```sh
brew install gtk4 libadwaita gtksourceview5 libspelling editorconfig gettext
```

## Run

Open `gnome-text-editor-macos-arm64-homebrew.dmg`, drag or open
`Text Editor.app`.
The app is ad-hoc signed, not notarized.
NOTES

hdiutil create -volname "GNOME Text Editor" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -fs HFS+ \
  -format UDZO \
  "$ARTIFACT"
shasum -a 256 "$ARTIFACT" > "$CHECKSUM"

echo "Release artifact: $ARTIFACT"
cat "$CHECKSUM"
