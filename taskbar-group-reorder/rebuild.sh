#!/usr/bin/env bash
# Rebuild + reinstall the patched libtaskmanager after a plasma-workspace upgrade.
#
# The patch enables real drag-reordering of window buttons WITHIN an inline
# task group (groupInline / groupPopups=false), which stock libtaskmanager
# refuses. See taskbar-group-reorder.patch and README.md.
#
# Runtime kill-switch (NO rebuild needed to toggle, just a plasmashell restart):
#   PLASMA_INTRA_GROUP_MOVES=0   -> old behaviour (intra-group moves refused)
#   unset / "1"                  -> patched behaviour (default ON)
set -euo pipefail
cd "$(dirname "$0")"

VER=$(pacman -Q plasma-workspace | awk '{print $2}' | cut -d- -f1)
SRC="plasma-workspace-$VER"
TAR="$SRC.tar.xz"

[ -f "$TAR" ] || curl -fLO "https://download.kde.org/stable/plasma/$VER/$TAR"
rm -rf "$SRC"
tar xf "$TAR"
cd "$SRC"

# Fails loudly if the patch no longer applies — port taskbar-group-reorder.patch first.
patch -p1 < ../taskbar-group-reorder.patch

# plasma-workspace configures cleanly, so we configure the whole tree once
# (cheap; compiles nothing) and then build ONLY the libtaskmanager target.
# The build dir is kept for fast incremental iterations.
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=OFF
cmake --build build --target taskmanager -j"$(nproc)"

# What plasmashell actually dlopen()s is the versioned SONAME file.
SOVER="$VER"
SO="build/bin/libtaskmanager.so.$SOVER"
DEST="/usr/lib/libtaskmanager.so.$SOVER"

# Sanity: the patched marker must be present in the freshly built library.
grep -q "PLASMA_INTRA_GROUP_MOVES" <(strings "$SO")

# Build-only: stop before any sudo/install/restart (see
# taskbar-compact-launchers/rebuild.sh for why).
if [ "${1:-}" = "--build-only" ]; then echo "BUILT: $SO"; exit 0; fi

# Back up the stock library once, then install the patched one.
# Unlink the destination first (new inode) instead of overwriting in place:
# overwriting a still-mmap'd .so under a running plasmashell can SIGBUS it.
# NB: backup must NOT live in /usr/lib with a lib-like name — ldconfig parses
# "libtaskmanager.so.6.7.2.stock" as a version candidate and re-points the
# .so.6 symlink at it (bit us 2026-07-13: intra-group drag silently reverted
# to stock). Keep backups in a subdir ldconfig ignores.
BAKDIR=/usr/lib/taskbar-patches-backup
sudo mkdir -p "$BAKDIR"
[ -f "$BAKDIR/$(basename "$DEST").stock" ] || sudo cp -a "$DEST" "$BAKDIR/$(basename "$DEST").stock"
# Refresh the stock backup from the installed package payload: a once-only copy
# goes stale on the next upgrade, and a revert performed with it would install a
# wrong-version library (see taskbar-compact-launchers/rebuild.sh).
PKG=$(ls -1 /var/cache/pacman/pkg/plasma-workspace-"$VER"-*.pkg.tar.zst 2>/dev/null | head -1)
if [ -n "$PKG" ]; then
    bsdtar -xOf "$PKG" "usr/lib/libtaskmanager.so.$SOVER" \
        | sudo tee "$BAKDIR/$(basename "$DEST").stock" >/dev/null
    sudo chmod 755 "$BAKDIR/$(basename "$DEST").stock"
else
    echo "WARNING: no cached plasma-workspace-$VER package; the lib .stock backup may be stale" >&2
fi
sudo rm -f "$DEST"
sudo cp "$SO" "$DEST"
# ldconfig may have re-pointed the .so.6 symlink while the .stock lived here;
# make sure it targets the real lib, then refresh the cache.
sudo ln -sfn "$(basename "$DEST")" "${DEST%.so.*}.so.6"
sudo ldconfig

systemctl --user restart plasma-plasmashell.service
echo "Patched libtaskmanager installed for plasma-workspace $VER."
