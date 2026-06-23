#!/usr/bin/env bash
# krill universal AppImage installer.
#
#   curl -fsSL https://krill-software.github.io/install.sh | bash -s <slug>
#
# Looks up the latest release of krill-software/<slug> on GitHub, downloads
# the AppImage to ~/.local/bin/krill-<slug>, marks it executable, and writes
# a .desktop entry into ~/.local/share/applications/ so it shows up in the
# launcher. Idempotent — running again upgrades to the latest release.
#
# No telemetry, no root, no surprise system changes. Reads only the public
# GitHub releases API; writes only inside $HOME.

set -euo pipefail

SLUG="${1:-}"
if [[ -z "$SLUG" ]]; then
  echo "usage: install.sh <slug>   (e.g. text-editor)" >&2
  exit 2
fi

REPO="krill-software/$SLUG"
API="https://api.github.com/repos/$REPO/releases/latest"

echo "==> Looking up latest release of $REPO"
META=$(curl -fsSL "$API")

TAG=$(printf '%s' "$META" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
APPIMAGE_URL=$(printf '%s' "$META" | grep -oE '"browser_download_url": *"[^"]+\.AppImage"' | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$TAG" || -z "$APPIMAGE_URL" ]]; then
  echo "could not find an AppImage in the latest release of $REPO" >&2
  exit 1
fi

# Pull a human-readable Name= for the .desktop entry from the release title
# ("Text Editor v0.1.6" → "Text Editor"); fall back to the slug.
RELEASE_NAME=$(printf '%s' "$META" | grep -m1 '"name"' | sed -E 's/.*"name": *"([^"]+)".*/\1/' || true)
DISPLAY_NAME="${RELEASE_NAME% v*}"
[[ -z "$DISPLAY_NAME" || "$DISPLAY_NAME" == "$RELEASE_NAME" ]] && DISPLAY_NAME="$SLUG"

BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"
DEST="$BIN_DIR/krill-$SLUG"
mkdir -p "$BIN_DIR" "$APP_DIR"

echo "==> Downloading $APPIMAGE_URL"
curl -fL --progress-bar "$APPIMAGE_URL" -o "$DEST"
chmod +x "$DEST"

# Install the icons the AppImage carries (hicolor tree at its root) into the
# user icon theme, so the launcher entry and the dock have something to show.
# --appimage-extract is built into the AppImage runtime (no FUSE needed).
ICON_DIR="$HOME/.local/share/icons/hicolor"
EXTRACT_TMP=$(mktemp -d)
if (cd "$EXTRACT_TMP" && "$DEST" --appimage-extract 'usr/share/icons/hicolor/*' > /dev/null 2>&1); then
  while IFS= read -r png; do
    size_dir=$(basename "$(dirname "$(dirname "$png")")")   # e.g. 128x128
    mkdir -p "$ICON_DIR/$size_dir/apps"
    cp -f "$png" "$ICON_DIR/$size_dir/apps/krill-$SLUG.png"
  done < <(find "$EXTRACT_TMP/squashfs-root/usr/share/icons/hicolor" -name '*.png' 2>/dev/null)
fi
rm -rf "$EXTRACT_TMP"

# Carry over the file-type associations Tauri baked into the AppImage's own
# .desktop (generated from the app's fileAssociations) so the launcher entry can
# be picked as a handler — and set as default — for those types. The bundled
# entry is the single source of truth; nothing app-specific is hardcoded here.
MIME=""
DESKTOP_TMP=$(mktemp -d)
if (cd "$DESKTOP_TMP" && "$DEST" --appimage-extract 'usr/share/applications/*.desktop' > /dev/null 2>&1); then
  BUNDLED=$(find "$DESKTOP_TMP/squashfs-root" -name '*.desktop' | head -n1)
  [[ -n "$BUNDLED" ]] && MIME=$(grep -m1 '^MimeType=' "$BUNDLED" | cut -d= -f2-)
fi
rm -rf "$DESKTOP_TMP"

# %f (a file path), not %U (a file:// URI): krill apps take a path argument.
cat > "$APP_DIR/krill-$SLUG.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$DISPLAY_NAME
Comment=$DISPLAY_NAME — part of the krill suite
Exec=$DEST %f
Icon=krill-$SLUG
Terminal=false
Categories=Utility;
StartupWMClass=krill-$SLUG
EOF
[[ -n "$MIME" ]] && printf 'MimeType=%s\n' "$MIME" >> "$APP_DIR/krill-$SLUG.desktop"

update-desktop-database "$APP_DIR" 2>/dev/null || true
gtk-update-icon-cache -q "$ICON_DIR" 2>/dev/null || true

case ":$PATH:" in
  *":$BIN_DIR:"*) PATH_NOTE="" ;;
  *) PATH_NOTE="
Add ~/.local/bin to PATH to launch it from the terminal:
  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
;;
esac

cat <<EOF

✓ Installed $DISPLAY_NAME $TAG to $DEST
  Launch via the application menu or 'krill-$SLUG'.$PATH_NOTE
EOF
