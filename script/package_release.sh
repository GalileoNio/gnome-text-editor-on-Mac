#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Text Editor"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
HOMEBREW_ARTIFACT="$DIST_DIR/gnome-text-editor-macos-arm64-homebrew.dmg"
BUNDLED_ARTIFACT="$DIST_DIR/gnome-text-editor-macos-arm64-bundled.dmg"
NOTES="$DIST_DIR/release-notes.md"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
BREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gnome-text-editor-dmg.XXXXXX")"
HOMEBREW_STAGE_DIR="$STAGE_ROOT/homebrew"
BUNDLED_STAGE_DIR="$STAGE_ROOT/bundled"

cleanup() {
  chmod -R u+w "$STAGE_ROOT" 2>/dev/null || true
  rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT

export PATH="$BREW_PREFIX/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

die() {
  echo "error: $*" >&2
  exit 1
}

copy_dir_contents() {
  local source_dir="$1"
  local target_dir="$2"

  [[ -d "$source_dir" ]] || return 0
  mkdir -p "$target_dir"
  cp -RL "$source_dir/." "$target_dir/"
}

stage_app() {
  local target_app="$1"

  mkdir -p "$(dirname "$target_app")"
  ditto --norsrc --noextattr --noqtn --noacl --nopersistRootless \
    "$APP_BUNDLE" "$target_app"
}

sign_app() {
  local app="$1"

  xattr -cr "$app" 2>/dev/null || true
  xattr -c "$app" 2>/dev/null || true
  codesign --force --deep --sign "$CODESIGN_IDENTITY" --timestamp=none "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
}

create_dmg() {
  local stage_dir="$1"
  local artifact="$2"

  hdiutil create -volname "GNOME Text Editor" \
    -srcfolder "$stage_dir" \
    -ov \
    -fs HFS+ \
    -format UDZO \
    "$artifact"
  shasum -a 256 "$artifact" > "$artifact.sha256"
}

is_macho() {
  local path="$1"

  file "$path" | grep -q "Mach-O"
}

array_contains() {
  local needle="$1"
  shift

  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done

  return 1
}

add_macho_file() {
  local path="$1"

  [[ -f "$path" ]] || return 0
  is_macho "$path" || return 0
  if [[ "${#MACHO_FILES[@]}" -gt 0 ]] &&
     array_contains "$path" "${MACHO_FILES[@]}"; then
    return 0
  fi
  MACHO_FILES+=("$path")
}

resolve_brew_dep() {
  local dep="$1"
  local macho="${2:-}"
  local name
  local candidate
  local loader_candidate

  if [[ "$dep" == "$BREW_PREFIX/"* ]]; then
    [[ -e "$dep" ]] || return 1
    realpath "$dep"
    return 0
  fi

  if [[ "$dep" == @rpath/* ]]; then
    name="${dep#@rpath/}"
    for candidate in "$BREW_PREFIX/lib/$name" "$BREW_PREFIX"/opt/*/lib/"$name"; do
      [[ -e "$candidate" ]] || continue
      realpath "$candidate"
      return 0
    done
  fi

  if [[ "$dep" == @loader_path/* && -n "$macho" ]]; then
    name="${dep#@loader_path/}"
    loader_candidate="$(dirname "$macho")/$name"
    if [[ -e "$loader_candidate" ]]; then
      loader_candidate="$(realpath "$loader_candidate")"
      if [[ "$loader_candidate" == "$BREW_PREFIX/"* ]]; then
        echo "$loader_candidate"
        return 0
      fi
    fi

    for candidate in "$BREW_PREFIX/lib/$name" "$BREW_PREFIX"/opt/*/lib/"$name"; do
      [[ -e "$candidate" ]] || continue
      realpath "$candidate"
      return 0
    done
  fi

  return 1
}

add_brew_lib() {
  local dep="$1"
  local macho="$2"
  local real_dep

  if ! real_dep="$(resolve_brew_dep "$dep" "$macho")"; then
    [[ "$dep" == "$BREW_PREFIX/"* ]] && die "missing Homebrew dependency: $dep"
    return 0
  fi

  if [[ "${#BREW_LIBS[@]}" -gt 0 ]] &&
     array_contains "$real_dep" "${BREW_LIBS[@]}"; then
    return 0
  fi
  BREW_LIBS+=("$real_dep")
}

enqueue_brew_deps() {
  local macho="$1"
  local dep

  while IFS= read -r dep; do
    add_brew_lib "$dep" "$macho"
  done < <(otool -L "$macho" | awk 'NR > 1 { print $1 }')
}

copy_brew_lib() {
  local source_lib="$1"
  local frameworks_dir="$2"
  local target_lib="$frameworks_dir/$(basename "$source_lib")"

  mkdir -p "$frameworks_dir"
  if [[ ! -e "$target_lib" ]]; then
    cp -L "$source_lib" "$target_lib"
    chmod u+w "$target_lib"
  fi
}

collect_macho_files() {
  local app="$1"
  local path
  local roots=(
    "$app/Contents/MacOS"
    "$app/Contents/Resources/_install/bin"
    "$app/Contents/Resources/_install/lib"
    "$app/Contents/Frameworks"
  )

  MACHO_FILES=()

  local root
  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r -d '' path; do
      add_macho_file "$path"
    done < <(find "$root" -type f -print0)
  done
}

rewrite_macho_links() {
  local app="$1"
  local dep
  local dep_real
  local framework_ref
  local macho
  local frameworks_dir="$app/Contents/Frameworks"

  collect_macho_files "$app"

  if [[ "${#MACHO_FILES[@]}" -gt 0 ]]; then
    for macho in "${MACHO_FILES[@]}"; do
      chmod u+w "$macho"

      if [[ "$macho" == "$frameworks_dir/"* ]]; then
        install_name_tool -id "@executable_path/../../../Frameworks/$(basename "$macho")" \
          "$macho" 2>/dev/null || true
      else
        install_name_tool -id "@loader_path/$(basename "$macho")" \
          "$macho" 2>/dev/null || true
      fi

      while IFS= read -r dep; do
        dep_real="$(resolve_brew_dep "$dep" "$macho" 2>/dev/null)" || continue
        framework_ref="@executable_path/../../../Frameworks/$(basename "$dep_real")"
        install_name_tool -change "$dep" "$framework_ref" "$macho"
      done < <(otool -L "$macho" | awk 'NR > 1 { print $1 }')
    done
  fi
}

copy_runtime_data() {
  local app="$1"
  local prefix="$app/Contents/Resources/_install"
  local pixbuf_cache="$prefix/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"

  copy_dir_contents "$BREW_PREFIX/share/gtk-4.0" "$prefix/share/gtk-4.0"
  copy_dir_contents "$BREW_PREFIX/share/gtksourceview-5" "$prefix/share/gtksourceview-5"
  copy_dir_contents "$BREW_PREFIX/share/glib-2.0/schemas" "$prefix/share/glib-2.0/schemas"
  copy_dir_contents "$BREW_PREFIX/share/icons/hicolor" "$prefix/share/icons/hicolor"
  copy_dir_contents "$BREW_PREFIX/share/mime" "$prefix/share/mime"
  copy_dir_contents "$BREW_PREFIX/lib/gdk-pixbuf-2.0" "$prefix/lib/gdk-pixbuf-2.0"

  if [[ -f "$pixbuf_cache" ]]; then
    sed -i.bak \
      "s|$BREW_PREFIX/lib/gdk-pixbuf-2.0/2.10.0/loaders|@GDK_PIXBUF_LOADER_DIR@|g" \
      "$pixbuf_cache"
    rm -f "$pixbuf_cache.bak"
  fi

  if command -v glib-compile-schemas >/dev/null 2>&1 &&
     [[ -d "$prefix/share/glib-2.0/schemas" ]]; then
    glib-compile-schemas "$prefix/share/glib-2.0/schemas"
  fi

  if command -v gtk4-update-icon-cache >/dev/null 2>&1 &&
     [[ -d "$prefix/share/icons/hicolor" ]]; then
    gtk4-update-icon-cache -q -t -f "$prefix/share/icons/hicolor"
  fi
}

bundle_homebrew_runtime() {
  local app="$1"
  local frameworks_dir="$app/Contents/Frameworks"
  local index=0
  local lib

  BREW_LIBS=()
  copy_runtime_data "$app"
  collect_macho_files "$app"

  local macho
  if [[ "${#MACHO_FILES[@]}" -gt 0 ]]; then
    for macho in "${MACHO_FILES[@]}"; do
      enqueue_brew_deps "$macho"
    done
  fi

  while [[ "$index" -lt "${#BREW_LIBS[@]}" ]]; do
    lib="${BREW_LIBS[$index]}"
    copy_brew_lib "$lib" "$frameworks_dir"
    enqueue_brew_deps "$lib"
    index=$((index + 1))
  done

  rewrite_macho_links "$app"
}

write_release_notes() {
  cat > "$NOTES" <<'NOTES'
# GNOME Text Editor for macOS

Unofficial macOS arm64 build of GNOME Text Editor.

## Artifacts

- `gnome-text-editor-macos-arm64-bundled.dmg`: includes the Homebrew GTK stack,
  related dynamic libraries, GTK runtime data, GtkSourceView data, gdk-pixbuf
  loaders, and the Adwaita icon theme. Users should not need to install the
  Homebrew runtime packages just to launch this build.
- `gnome-text-editor-macos-arm64-homebrew.dmg`: smaller package that links
  against Homebrew libraries already installed on the user's machine.

## Requirements for the Homebrew Package

```sh
brew install gtk4 libadwaita gtksourceview5 libspelling editorconfig gettext adwaita-icon-theme
```

## Run

Open the DMG, then drag or open `Text Editor.app`.
Both packages are ad-hoc signed, not notarized.
NOTES
}

"$ROOT_DIR/script/build_and_run.sh" --no-launch

stage_app "$HOMEBREW_STAGE_DIR/$APP_NAME.app"
sign_app "$HOMEBREW_STAGE_DIR/$APP_NAME.app"
create_dmg "$HOMEBREW_STAGE_DIR" "$HOMEBREW_ARTIFACT"

stage_app "$BUNDLED_STAGE_DIR/$APP_NAME.app"
bundle_homebrew_runtime "$BUNDLED_STAGE_DIR/$APP_NAME.app"
sign_app "$BUNDLED_STAGE_DIR/$APP_NAME.app"
create_dmg "$BUNDLED_STAGE_DIR" "$BUNDLED_ARTIFACT"

write_release_notes

echo "Release artifacts:"
cat "$HOMEBREW_ARTIFACT.sha256"
cat "$BUNDLED_ARTIFACT.sha256"
