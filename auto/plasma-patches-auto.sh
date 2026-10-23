#!/usr/bin/env bash
# Re-apply the out-of-tree Plasma taskbar/tray patches if pacman reverted them.
#
# Installed as /usr/local/sbin/plasma-patches-auto, run as root by
# plasma-patches-rebuild.service, which is started by:
#   - the pacman hook (PostTransaction, --no-block) after an upgrade of
#     plasma-desktop / plasma-workspace, and
#   - every boot (multi-user.target), which catches upgrades whose transaction
#     died before PostTransaction (2026-10-20: a failed extraction meant no hook
#     ran at all and the patches sat reverted).
#
# Idempotent and cheap when nothing is needed: it verifies the patch markers in
# the installed binaries and exits 0 without touching anything.
#
#   --check   report state (exit 0 = patched), no logging, no builds
#
# Builds run as the owning user (no sudo, no password), installs run as root.
# A patch that no longer applies aborts before any install: the working stock
# binaries stay in place and the user is told a port is needed.
set -uo pipefail

REPO=/home/x/Documents/projects/plasma-taskbar-patches
OWNER=x
OWNER_UID=1000
AP=/usr/lib/qt6/plugins/plasma/applets
BAKDIR=/usr/lib/taskbar-patches-backup
LOG=/var/log/plasma-patches-auto.log
SERVICE=plasma-patches-rebuild.service

pkgver() { pacman -Q "$1" 2>/dev/null | awk '{print $2}' | cut -d- -f1; }

patched() {
    local wv
    wv=$(pkgver plasma-workspace)
    [ -n "$wv" ] || return 1
    grep -q explicitPlacement <(strings -e l "$AP/org.kde.plasma.taskmanager.so" 2>/dev/null) &&
        grep -q itemOrder <(strings -e l "$AP/org.kde.plasma.systemtray.so" 2>/dev/null) &&
        grep -q PLASMA_INTRA_GROUP_MOVES <(strings "/usr/lib/libtaskmanager.so.$wv" 2>/dev/null)
}

if [ "${1:-}" = "--check" ]; then
    patched && exit 0
    exit 1
fi

exec >>"$LOG" 2>&1
echo "=== $(date -Is) plasma-patches-auto start"

asowner() {
    runuser -u "$OWNER" -- env \
        XDG_RUNTIME_DIR="/run/user/$OWNER_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$OWNER_UID/bus" \
        "$@"
}

notify() {
    # Best effort: no session bus when the rebuild is triggered while logged out.
    asowner notify-send -a "Plasma patches" "$@" 2>/dev/null || true
}

fail() {
    echo "FAIL: $1"
    notify -u critical "Plasma patch re-apply FAILED" \
        "$1 — the stock taskbar/tray is still in place. Log: $LOG"
    exit 1
}

# Wait for a running pacman to finish: the hook fires from inside the
# transaction, this service must not race the database lock.
for _ in $(seq 900); do
    [ -e /var/lib/pacman/db.lck ] || break
    sleep 2
done

if patched; then
    echo "already patched, nothing to do"
    exit 0
fi

DV=$(pkgver plasma-desktop)
WV=$(pkgver plasma-workspace)
[ -n "$DV" ] && [ -n "$WV" ] || fail "cannot determine plasma-desktop/plasma-workspace version"

# Build only (as the owner). Aborts on a patch that no longer applies.
for d in taskbar-compact-launchers taskbar-group-reorder systray-2rows; do
    echo "--- build $d"
    runuser -u "$OWNER" -- bash -c "cd '$REPO/$d' && ./rebuild.sh --build-only" ||
        fail "$d: patch no longer applies or build failed (port needed)"
done

TM="$REPO/taskbar-compact-launchers/plasma-desktop-$DV/build/bin/plasma/applets/org.kde.plasma.taskmanager.so"
ST="$REPO/systray-2rows/plasma-workspace-$WV/build/bin/plasma/applets/org.kde.plasma.systemtray.so"
LT="$REPO/taskbar-group-reorder/plasma-workspace-$WV/build/bin/libtaskmanager.so.$WV"
for f in "$TM" "$ST" "$LT"; do
    [ -f "$f" ] || fail "missing build output $f"
done

# Refresh the stock revert backups from the package payloads, so a revert never
# installs a binary from an older Plasma release.
refresh_stock() { # $1=pkgname $2=version $3=member-path $4=backup-dest
    local p
    p=$(ls -1 /var/cache/pacman/pkg/"$1"-"$2"-*.pkg.tar.zst 2>/dev/null | head -1)
    if [ -n "$p" ]; then
        bsdtar -xOf "$p" "$3" >"$4.tmp" && chmod 755 "$4.tmp" && mv -f "$4.tmp" "$4"
    else
        echo "WARN: no cached $1-$2 package; $4 left as is"
    fi
}
mkdir -p "$BAKDIR"
refresh_stock plasma-desktop "$DV" usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.taskmanager.so \
    "$AP/org.kde.plasma.taskmanager.so.stock"
refresh_stock plasma-workspace "$WV" usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.systemtray.so \
    "$AP/org.kde.plasma.systemtray.so.orig"
refresh_stock plasma-workspace "$WV" "usr/lib/libtaskmanager.so.$WV" \
    "$BAKDIR/libtaskmanager.so.$WV.stock"

# Install on a NEW inode: overwriting a still-mmap'd .so can SIGBUS the running
# plasmashell (same reason taskbar-group-reorder/rebuild.sh unlinks first).
put() { install -m 755 "$1" "$2.new" && mv -f "$2.new" "$2"; }
put "$TM" "$AP/org.kde.plasma.taskmanager.so" || fail "install taskmanager.so"
put "$ST" "$AP/org.kde.plasma.systemtray.so" || fail "install systemtray.so"
put "$LT" "/usr/lib/libtaskmanager.so.$WV" || fail "install libtaskmanager.so.$WV"
ln -sfn "libtaskmanager.so.$WV" /usr/lib/libtaskmanager.so.6
ldconfig

patched || fail "installed the built binaries but the patch markers are missing"

# Pick the new plugins up. If no graphical session is running the binaries are
# simply there at next login.
asowner systemctl --user restart plasma-plasmashell.service ||
    echo "WARN: could not restart plasmashell (no user session?)"

echo "OK: re-applied for plasma-desktop $DV / plasma-workspace $WV"
notify "Plasma patches re-applied" "Rebuilt for Plasma $DV (taskbar, tray, libtaskmanager)."
exit 0
