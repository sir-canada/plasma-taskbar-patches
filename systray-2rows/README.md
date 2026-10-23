# systray-2rows — 2-row system tray on a 44px panel

Patched `org.kde.plasma.systemtray.so` (plasma-workspace) adding:
1. Corrected multi-row threshold: n rows need `n·icon + (n−1)·spacing` (2 rows at 48px instead of 52, standard icons).
2. New **"Very small" (16px)** choice under System Tray settings → *Panel icon size* (config key `useVerySmallIcons`, default off).
3. **Drag-to-reorder tray icons** (second patch, see below).

With "Very small" on and no margins-separator widget next to the tray, 2 rows fit a 44px panel (36px usable = 2×16+4).

## Feature: drag-to-reorder tray icons (systray-drag-reorder.patch)

Drag an icon in the visible tray with the left button past the drag threshold
(~10px) and drop it on another cell — a floating copy of the icon follows the
pointer, the original dims while dragging. Clicks, wheel and press-and-hold are
unaffected (the drag steals the grab only after the threshold).

- **Config key**: `itemOrder` (StringList, group `General` of the systray applet
  in `plasma-org.kde.plasma.desktop-appletsrc`). The first drag writes the full
  visible order (list of item ids) and engages *manual order mode*; the C++
  `SortedSystemTrayModel` then sorts by list position instead of category+name.
- **Append semantics**: ids not in the list (new/unknown apps, items appearing
  from the hidden popup) sort *after* all listed items using the stock rules.
  Dragging again captures them into the list.
- **Notifications-first override**: stock forces `org.kde.plasma.notifications`
  to the first slot; manual mode disables that special case (otherwise the bell
  would be unmovable). Unlisted, it sorts last like any unknown id.
- **Kill switch**: delete the key → stock sorting returns.
  `kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc --group Containments --group 84 --group Applets --group 89 --group General --key itemOrder --delete`
  (plasmashell stopped, then restart).
- The order is saved to disk immediately on drop (survives crashes/SIGKILL).

## Files
- `systray-2rows.patch` — the source patch (3 files under `applets/systemtray/`)
- `systray-drag-reorder.patch` — drag-to-reorder patch (7 files); applies **on top of** systray-2rows.patch
- `rebuild.sh` — re-fetch matching source, apply both patches, build, install, restart plasmashell
- `MR-DESCRIPTION.md` — MR text for the upstream KDE Invent submission
  (fork `sircanada/plasma-workspace`, branch `work/systray-very-small-icons`)
- `screenshots/` — tray verification captures

## After a plasma-workspace upgrade
Pacman replaces the patched plugin. Re-apply with:

    ./rebuild.sh

If `patch` fails, the upstream code changed — port the failing patch
(`systray-2rows.patch` and/or `systray-drag-reorder.patch`; the latter is
generated against a tree that already has the former applied).

## Restore stock behavior
    sudo cp -a /usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.systemtray.so.orig \
               /usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.systemtray.so
    systemctl --user restart plasma-plasmashell.service

(or simply reinstall: `sudo pacman -S plasma-workspace`)

Toggle the feature off without restoring: System Tray settings → Panel icon size → "Small",
or `kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc --group Containments --group 84 --group Applets --group 89 --group General --key useVerySmallIcons false` + plasmashell restart.
