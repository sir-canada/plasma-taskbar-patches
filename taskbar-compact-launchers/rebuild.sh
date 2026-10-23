#!/usr/bin/env bash
# Rebuild + reinstall the patched Task Manager applet after a plasma-desktop upgrade.
# The patch gives every task an explicit GridLayout row/column on multi-row
# horizontal panels so leading launchers stack R-per-column in narrow
# (row-height wide) columns instead of each launcher stretching to a full task
# width. See taskbar-compact-launchers.patch and README.md.
set -euo pipefail
cd "$(dirname "$0")"

VER=$(pacman -Q plasma-desktop | awk '{print $2}' | cut -d- -f1)
SRC="plasma-desktop-$VER"
TAR="$SRC.tar.xz"

[ -f "$TAR" ] || curl -fLO "https://download.kde.org/stable/plasma/$VER/$TAR"
rm -rf "$SRC"
tar xf "$TAR"
cd "$SRC"

# Fails loudly if the patch no longer applies — port taskbar-compact-launchers.patch first.
patch -p1 < ../taskbar-compact-launchers.patch

# plasma-desktop is a big tree with optional deps we do not need; build ONLY the
# taskmanager applet. Trim the top-level CMakeLists to just that subdir so we do
# not have to satisfy KCM / attica-kde / X11 build dependencies.
python3 - <<'PY'
import re, pathlib
p = pathlib.Path("CMakeLists.txt")
t = p.read_text()
block = re.search(r"add_subdirectory\(layout-templates\).*?add_subdirectory\(kaccess\)\nendif\(\)",
                  t, re.S)
if block:
    t = t.replace(block.group(0),
                  "# taskbar-compact-launchers: only build the taskmanager applet plugin.\n"
                  "add_subdirectory(applets/taskmanager)")
t = t.replace("add_subdirectory(appiumtests)",
              "# taskbar-compact-launchers: appiumtests not needed\n# add_subdirectory(appiumtests)")
p.write_text(t)
PY

cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
    -DBUILD_TESTING=OFF -DBUILD_KCM_TOUCHPAD_X11=OFF -DBUILD_KCM_MOUSE_X11=OFF
cmake --build build --target org.kde.plasma.taskmanager -j"$(nproc)"

SO=build/bin/plasma/applets/org.kde.plasma.taskmanager.so
DEST=/usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.taskmanager.so

# Sanity: the patched identifier must be inside (QML cache stores UTF-16 LE).
# Process substitution, not a pipe: grep -q exits early and pipefail would
# turn the resulting SIGPIPE in strings into a bogus 141 failure.
grep -q "explicitPlacement" <(strings -e l "$SO")

# Build-only: stop before any sudo/install/restart. Used by
# /usr/local/sbin/plasma-patches-auto, which builds as the user and installs as
# root, so the unattended path never needs an interactive sudo password.
if [ "${1:-}" = "--build-only" ]; then echo "BUILT: $SO"; exit 0; fi

# Back up the stock plugin, then install the patched one.
# The backup is refreshed from the INSTALLED PACKAGE's payload, not from $DEST:
# $DEST is already patched once this script has run before, and a once-only copy
# goes stale on the next Plasma upgrade -- reverting with a stale .stock would
# install a binary from an older release and the applet would fail to load.
PKG=$(ls -1 /var/cache/pacman/pkg/plasma-desktop-"$VER"-*.pkg.tar.zst 2>/dev/null | head -1)
if [ -n "$PKG" ]; then
    bsdtar -xOf "$PKG" usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.taskmanager.so \
        | sudo tee "$DEST.stock" >/dev/null
    sudo chmod 755 "$DEST.stock"
else
    echo "WARNING: no cached plasma-desktop-$VER package; $DEST.stock may be stale" >&2
    [ -f "$DEST.stock" ] || sudo cp -a "$DEST" "$DEST.stock"
fi
sudo cp "$SO" "$DEST"

systemctl --user restart plasma-plasmashell.service
echo "Patched taskmanager applet installed for plasma-desktop $VER."
