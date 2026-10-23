#!/usr/bin/env bash
# Re-apply ALL out-of-tree Plasma taskbar patches after a plasma-desktop /
# plasma-workspace upgrade (the "upgrade treadmill" — pacman overwrites the
# patched binaries with stock ones on every upgrade, silently reverting the
# features). Run this after each Plasma upgrade.
#
# Triggered as a reminder by /etc/pacman.d/hooks/plasma-taskbar-patches.hook.
set -euo pipefail
cd "$(dirname "$0")"

# Order: applet patches first, library patch last (the lib restart is heaviest).
for d in taskbar-compact-launchers taskbar-group-reorder systray-2rows; do
  echo "=== reapply: $d ==="
  ( cd "$d" && ./rebuild.sh )
done

echo "All plasma-taskbar-patches re-applied."
