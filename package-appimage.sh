#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/codex-app"
TMP_DIR="$ROOT_DIR/tmp"
ASSETS_DIR="$ROOT_DIR/assets"

info() { echo "$*" >&2; }

ensure_appimagetool() {
  local tool_path="$TMP_DIR/appimagetool"
  if [ -x "$tool_path" ]; then
    echo "$tool_path"
    return
  fi

  info "Downloading appimagetool..."
  local url="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
  mkdir -p "$TMP_DIR"
  curl -L -o "$tool_path" "$url" --progress-bar --max-time 120
  if [ ! -f "$tool_path" ]; then
    echo "Failed to download appimagetool to $tool_path" >&2
    exit 1
  fi
  chmod +x "$tool_path"
  echo "$tool_path"
}

assemble_appdir() {
  if [ ! -d "$APP_DIR" ]; then
    echo "codex-app not found. Run make build first." >&2
    exit 1
  fi

  local appdir="$TMP_DIR/AppDir"
  rm -rf "$appdir"
  mkdir -p "$appdir"
  cp -r "$APP_DIR/"* "$appdir/"

  cat > "$appdir/AppRun" << 'APP_RUN'
#!/usr/bin/env bash
set -euo pipefail

appdir=$(dirname "$(readlink -f "$0")")
appimage_path="$(readlink -f "$0")"
[[ -n ${APPIMAGE:-} ]] && appimage_path="$APPIMAGE"

integrate_desktop() {
  local desktop_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  local icon_dir="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
  local desktop_file="$desktop_dir/codex-appimage.desktop"

  mkdir -p "$desktop_dir" "$icon_dir" 2>/dev/null || true

  if [[ -f $appdir/codex.png ]]; then
    local icon_dest="$icon_dir/codex.png"
    if [[ ! -f $icon_dest ]] || ! cmp -s "$appdir/codex.png" "$icon_dest"; then
      cp "$appdir/codex.png" "$icon_dest" 2>/dev/null || true
    fi
  fi

  local current_exec=''
  [[ -f $desktop_file ]] && current_exec=$(grep '^Exec=' "$desktop_file" 2>/dev/null | head -1)
  if [[ ! -f $desktop_file ]] || [[ $current_exec != "Exec=env CODEX_CLI_PATH=${CODEX_CLI_PATH:-} \"${appimage_path}\" %U" ]]; then
    cat > "$desktop_file" << DESKTOP
[Desktop Entry]
Name=Codex
Exec=env CODEX_CLI_PATH=${CODEX_CLI_PATH:-} "${appimage_path}" %U
Icon=codex
Type=Application
Terminal=false
Categories=Utility;
StartupWMClass=Codex
DESKTOP
  fi

  update-desktop-database "$desktop_dir" 2>/dev/null || true
}

find_codex_cli() {
  if [[ -n ${CODEX_CLI_PATH:-} ]] && [[ -x ${CODEX_CLI_PATH} ]]; then
    echo "$CODEX_CLI_PATH"
    return
  fi

  if command -v codex >/dev/null 2>&1; then
    command -v codex
    return
  fi

  local candidates=(
    "$HOME/.nvm/versions/node/"*/bin/codex
    "$HOME/.local/bin/codex"
    "/usr/local/bin/codex"
    "/usr/bin/codex"
  )

  local c
  for c in "${candidates[@]}"; do
    if [[ -x $c ]]; then
      echo "$c"
      return
    fi
  done

  echo ""
}

export CODEX_CLI_PATH="${CODEX_CLI_PATH:-$(find_codex_cli)}"

integrate_desktop

exec "$appdir/start.sh" "$@"
APP_RUN

  chmod +x "$appdir/AppRun"

  cat > "$appdir/codex.desktop" << 'DESKTOP_FILE'
[Desktop Entry]
Name=Codex
Exec=codex %U
Icon=codex
Type=Application
Terminal=false
Categories=Utility;
StartupWMClass=Codex
DESKTOP_FILE

  local icon_src="$ASSETS_DIR/codex.png"
  local icon_dest="$appdir/codex.png"
  if [ -f "$icon_src" ]; then
    cp "$icon_src" "$icon_dest"
    info "  Icon: $icon_src"
  else
    echo "  WARNING: assets/codex.png not found; AppImage will use default icon" >&2
  fi

  echo "$appdir"
}

build_appimage() {
  local appdir="$1"
  local default_appimage="$ROOT_DIR/Codex-x86_64.AppImage"
  local appimage_file="$default_appimage"

  if [ -f "$appimage_file" ]; then
    if ! rm -f "$appimage_file" 2>/dev/null; then
      local stamp
      stamp="$(date -Iseconds | tr ':.+' '---')"
      appimage_file="$ROOT_DIR/Codex-x86_64-$stamp.AppImage"
      echo "  WARNING: $default_appimage is busy; writing to $appimage_file" >&2
    fi
  fi

  local tool
  tool="$(ensure_appimagetool)"

  if ! ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$appimage_file"; then
    info "  Retrying with extracted appimagetool..."
    local extracted="$TMP_DIR/appimagetool-extracted"
    if [ ! -d "$extracted" ]; then
      (cd "$TMP_DIR" && "$tool" --appimage-extract)
      mv "$TMP_DIR/squashfs-root" "$extracted"
    fi
    ARCH=x86_64 "$extracted/AppRun" "$appdir" "$appimage_file"
  fi

  chmod +x "$appimage_file"
  local size
  size="$(du -m "$appimage_file" | cut -f1)"
  echo ""
  echo "  AppImage: $appimage_file"
  echo "  Size: ${size} MB"
}

main() {
  info "=== Packaging Codex as AppImage ==="
  echo ""
  mkdir -p "$TMP_DIR"
  local appdir
  appdir="$(assemble_appdir)"
  build_appimage "$appdir"
}

main "$@"
