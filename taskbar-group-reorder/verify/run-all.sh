#!/usr/bin/env bash
# Run the full libtaskmanager tasksmodeltest suite against the patched build.
# Expects a test-enabled build tree (cmake ... -DBUILD_TESTING=ON) at
# ../plasma-workspace-<ver>/build-test. Run under a nested headless KWin:
#   kwin_wayland --virtual  (with KWIN_WAYLAND_NO_PERMISSION_CHECKS=1)
set -euo pipefail
BUILD_BIN="$(cd "$(dirname "$0")/.." && pwd)/plasma-workspace-$(pacman -Q plasma-workspace | awk '{print $2}' | cut -d- -f1)/build-test/bin"
export QT_QPA_PLATFORM=wayland
export LD_LIBRARY_PATH="$BUILD_BIN:${LD_LIBRARY_PATH:-}"
export QT_LOGGING_RULES="qt.qpa.*=false;org.kde.plasma.libtaskmanager=false"
"$BUILD_BIN/tasksmodeltest"
