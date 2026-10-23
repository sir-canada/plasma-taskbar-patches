#!/usr/bin/env bash
# Rebuild + reinstall the patched systemtray plugin after a plasma-workspace upgrade.
# Patches applied, in order:
#   1. systray-2rows.patch       — "Very small" (16px) icon size + multi-row threshold fix
#   2. systray-drag-reorder.patch — drag-to-reorder tray icons (itemOrder config key)
# See README.md.
set -euo pipefail
cd "$(dirname "$0")"

VER=$(pacman -Q plasma-workspace | awk '{print $2}' | cut -d- -f1)
SRC="plasma-workspace-$VER"
TAR="$SRC.tar.xz"

[ -f "$TAR" ] || curl -fLO "https://download.kde.org/stable/plasma/$VER/$TAR"
rm -rf "$SRC"
tar xf "$TAR"
cd "$SRC"

# Fails loudly if a patch no longer applies — port the failing patch first.
# Order matters: systray-drag-reorder.patch is generated on top of systray-2rows.patch.
patch -p1 < ../systray-2rows.patch
patch -p1 < ../systray-drag-reorder.patch

cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=OFF
cmake --build build --target org.kde.plasma.systemtray -j"$(nproc)"

SO=build/bin/plasma/applets/org.kde.plasma.systemtray.so
DEST=/usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.systemtray.so

# Sanity: patched string literals must be inside (QML cache / QStringLiteral store UTF-16 LE).
# Process substitution, not a pipe: grep -q exits early and pipefail would turn the
# resulting SIGPIPE in strings into a bogus 141 failure that aborts before install.
grep -q "Very small" <(strings -e l "$SO")   # systray-2rows.patch
grep -q "itemOrder"  <(strings -e l "$SO")   # systray-drag-reorder.patch

# Build-only: stop before any sudo/install/restart (see
# taskbar-compact-launchers/rebuild.sh for why).
if [ "${1:-}" = "--build-only" ]; then echo "BUILT: $SO"; exit 0; fi

[ -f "$DEST.orig" ] || sudo cp -a "$DEST" "$DEST.orig"
# Refresh the stock backup from the installed package payload (see the same
# block in taskbar-compact-launchers/rebuild.sh for why a once-only copy is
# wrong: it goes stale on the next upgrade and a revert then installs a
# wrong-version plugin).
PKG=$(ls -1 /var/cache/pacman/pkg/plasma-workspace-"$VER"-*.pkg.tar.zst 2>/dev/null | head -1)
if [ -n "$PKG" ]; then
    bsdtar -xOf "$PKG" usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.systemtray.so \
        | sudo tee "$DEST.orig" >/dev/null
    sudo chmod 755 "$DEST.orig"
else
    echo "WARNING: no cached plasma-workspace-$VER package; $DEST.orig may be stale" >&2
fi
sudo cp "$SO" "$DEST"
systemctl --user restart plasma-plasmashell.service
echo "Patched systemtray plugin installed for plasma-workspace $VER."
