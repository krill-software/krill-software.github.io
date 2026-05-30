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

cat > "$APP_DIR/krill-$SLUG.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$DISPLAY_NAME
Comment=$DISPLAY_NAME — part of the krill suite
Exec=$DEST %U
Terminal=false
Categories=Utility;
StartupWMClass=krill-$SLUG
EOF

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
