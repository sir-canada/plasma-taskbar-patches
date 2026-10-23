#!/usr/bin/env bash
# Install the settings GUI to ~/.local/bin + application menu entry.
set -euo pipefail
cd "$(dirname "$0")"

python3 -c "import PySide6" 2>/dev/null || {
    echo "PySide6 missing. Install it first: sudo pacman -S pyside6"; exit 1; }

install -Dm755 taskbar-compact-settings "$HOME/.local/bin/taskbar-compact-settings"
install -Dm644 taskbar-compact-settings.desktop \
    "$HOME/.local/share/applications/taskbar-compact-settings.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

echo "Installed. Launch 'Taskbar Compact Settings' from the app menu"
echo "or run: taskbar-compact-settings"
