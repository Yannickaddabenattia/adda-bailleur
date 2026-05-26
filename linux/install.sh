#!/usr/bin/env bash
#
# Installation utilisateur (sans sudo) de ADDA Bailleur sur Linux.
# Enregistre les associations de fichiers .adlb / .adlr / .adli pour que
# le double-clic depuis le gestionnaire de fichiers ouvre l'application
# directement.
#
# Usage : depuis la racine du projet AddaLocation, après `flutter build linux --release` :
#   ./linux/install.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_SRC="$ROOT_DIR/build/linux/x64/release/bundle"
APP_NAME="adda_location"

if [ ! -d "$BUNDLE_SRC" ]; then
  echo "ERREUR : bundle introuvable à $BUNDLE_SRC"
  echo "Lance d'abord :  ~/flutter/bin/flutter build linux --release"
  exit 1
fi

INSTALL_DIR="$HOME/.local/share/$APP_NAME"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
MIME_DIR="$HOME/.local/share/mime/packages"
ICON_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"

mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$DESKTOP_DIR" "$MIME_DIR" "$ICON_DIR"

echo "→ Copie du bundle vers $INSTALL_DIR/"
rm -rf "$INSTALL_DIR"
cp -R "$BUNDLE_SRC" "$INSTALL_DIR"

echo "→ Lien binaire dans $BIN_DIR/$APP_NAME"
ln -sf "$INSTALL_DIR/$APP_NAME" "$BIN_DIR/$APP_NAME"

if [ -f "$ROOT_DIR/assets/images/logo_square.png" ]; then
  echo "→ Icône applicative"
  cp "$ROOT_DIR/assets/images/logo_square.png" "$ICON_DIR/adda-bailleur.png"
fi

echo "→ Entrée de bureau (.desktop)"
sed "s|^Exec=adda_location|Exec=$INSTALL_DIR/$APP_NAME|" \
  "$SCRIPT_DIR/adda-bailleur.desktop" \
  > "$DESKTOP_DIR/adda-bailleur.desktop"

echo "→ Types MIME (.adlb / .adlr / .adli)"
cp "$SCRIPT_DIR/adda-bailleur-mime.xml" \
  "$MIME_DIR/adda-bailleur.xml"

echo "→ Mise à jour des bases système"
if command -v update-mime-database >/dev/null; then
  update-mime-database "$HOME/.local/share/mime" || true
fi
if command -v update-desktop-database >/dev/null; then
  update-desktop-database "$DESKTOP_DIR" || true
fi
if command -v gtk-update-icon-cache >/dev/null; then
  gtk-update-icon-cache --quiet "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
fi

echo "→ Associations par défaut"
if command -v xdg-mime >/dev/null; then
  xdg-mime default adda-bailleur.desktop application/x-adda-backup || true
  xdg-mime default adda-bailleur.desktop application/x-adda-signed-edl || true
  xdg-mime default adda-bailleur.desktop application/x-adda-intervention || true
fi

cat <<EOM

✔ ADDA Bailleur installé.

Binaire     : $INSTALL_DIR/$APP_NAME
Lanceur     : $DESKTOP_DIR/adda-bailleur.desktop

Tu peux maintenant :
  - lancer l'app depuis le menu d'applications (chercher "ADDA Bailleur")
  - double-cliquer un .adlb / .adlr / .adli reçu : il s'ouvre directement

Si l'icône ou l'association n'apparaît pas tout de suite, déconnecte/reconnecte
la session, ou exécute :  killall -HUP gnome-shell  (sur GNOME/Zorin)

EOM
