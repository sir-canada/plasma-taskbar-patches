#!/usr/bin/env bash
# Run only the added test_intraGroupMove case against the patched build.
# Same prerequisites as run-all.sh.
set -euo pipefail
BUILD_BIN="$(cd "$(dirname "$0")/.." && pwd)/plasma-workspace-$(pacman -Q plasma-workspace | awk '{print $2}' | cut -d- -f1)/build-test/bin"
export QT_QPA_PLATFORM=wayland
export LD_LIBRARY_PATH="$BUILD_BIN:${LD_LIBRARY_PATH:-}"
export QT_LOGGING_RULES="qt.qpa.*=false"
"$BUILD_BIN/tasksmodeltest" test_intraGroupMove
