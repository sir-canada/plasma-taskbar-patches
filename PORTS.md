# Patch rebase log (versions these patches were ported to)

The patches target KDE source that moves under us. This file records what had to
be changed, so the next upgrade is a known quantity.

## 6.8.0 — 2026-10-20

Built against `plasma-desktop-6.8.0` / `plasma-workspace-6.8.0`, installed on
Plasma 6.8.0 (Qt 6.12, KF 6.31), CachyOS Wayland.

| Patch | Applied cleanly? | Work done |
|---|---|---|
| `systray-2rows/systray-2rows.patch` | yes (hunk offset +14) | none |
| `systray-2rows/systray-drag-reorder.patch` | yes (`systemtray.cpp` offset −48) | none |
| `taskbar-group-reorder/taskbar-group-reorder.patch` | yes (`tasksmodel.cpp` offset −44) | none |
| `taskbar-compact-launchers/taskbar-compact-launchers.patch` | **no — 1/9 hunks failed** | rebased (below) |

### The taskbar rebase

Hunk 3 of `Task.qml` inserts the Claude-state / flat-visual block after the
`highlighted` property, with trailing context:

```qml
    active: !inPopup && !tasksRoot.groupDialog && task.contextMenu?.status !== PlasmaExtras.Menu.Open
    interactive: model.IsWindow || mainItem.playerData
    location: Plasmoid.location
```

In 6.8.0 upstream appended a condition to that `active:` line
(plasma-desktop commit touching tooltip-on-click ownership):

```qml
    active: !inPopup && !tasksRoot.groupDialog && task.contextMenu?.status !== PlasmaExtras.Menu.Open && task === (tasksRoot.toolTipOpenedByClick ?? task)
```

Only the context changed — no patched line needed editing. The block was
re-inserted at the same anchor (immediately after the `highlighted` binding,
before `active:`) and the whole patch was regenerated from a pristine 6.8.0
tree so all hunks carry correct context and need no fuzz. Verified by applying
the regenerated patch to a fresh extract and comparing byte-for-byte against the
ported tree for all five touched files (`Task.qml`, `TaskList.qml`,
`main.qml`, `MouseHandler.qml`, `PulseAudio.qml`).

Previous patch kept as `taskbar-compact-launchers.patch.bak-pre6.8`.

### Post-install verification used

```sh
strings -e l /usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.taskmanager.so \
  | grep -cE 'explicitPlacement|claudeStyle|wheelVolume'      # expect 6
strings -e l /usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.systemtray.so \
  | grep -cE 'Very small|itemOrder'                            # expect 3
strings /usr/lib/libtaskmanager.so.6.8.0 | grep -c PLASMA_INTRA_GROUP_MOVES   # expect 1
```

Also worth eyeballing: two task rows, launcher column stacking, 16px tray icons
in two rows, wheel-volume over the taskbar.

### Known startup noise (not caused by the patches)

`BackgroundAppItem.qml:20-23,32,76: TypeError: Cannot read property '<role>' of
null` — a burst of 6 lines per tray item at every plasmashell start on 6.8.0.

Verified by A/B on the same session: installing the stock 6.8.0 `systemtray.so`
from `pacman` and restarting plasmashell gives the **same 78 lines**; the
patched build gives 78 too. Transient delegate-model initialisation (the
`ItemLoader.setSource` initialProperties land after the first binding
evaluation), no user-visible effect — the tray renders all items. Don't chase it
as a patch regression.

### Stock revert backups were stale (fixed 2026-10-20)

The `.stock` / `.orig` backups were written **once**, so by the time 6.8.0 landed
`taskmanager.so.stock` was still a 6.7.2 binary — following the documented revert
(`sudo cp …taskmanager.so.stock …taskmanager.so`) would have installed a
wrong-version applet. All three `rebuild.sh` scripts now refresh their stock
backup from the **installed package payload**
(`bsdtar -xOf /var/cache/pacman/pkg/plasma-*-$VER-*.pkg.tar.zst …`) on every run,
falling back to the old once-only copy with a warning if the package is no longer
cached. The three backups on this machine were refreshed from the 6.8.0 packages
and verified to be marker-free.

## Taskbar labels rendered with LCD subpixel antialiasing — fixed 2026-10-20

**Symptom:** after the 6.8.0 upgrade the taskbar titles looked blurry/"squished"
and, at 10px, hard to read — colour fringes rather than sharp text. Unrelated to
font size or family (7, 7.5, 8, 14 pt and DejaVu/Noto all behaved the same).

**Root cause:** on this stack (Qt 6.12.0 + FreeType 2.15.0, both upgraded in the
same transaction as Plasma 6.8.0) the patched label renders with **LCD subpixel
antialiasing**, while stock Plasma text stays grayscale. Nothing in the patch
set it explicitly; Qt Quick just picks it for that item.

**How it was measured** — mean per-pixel RGB spread over text pixels (0 = pure
grayscale, ~60+ = RGB fringing), text-only column runs so icons don't skew it:

| target | chroma |
|---|---|
| stock 6.8.0 taskbar (`.so.stock`) | 1–6 |
| patched, `QtRendering` | 62–73 |
| patched, `Text.NativeRendering` | **1.5** |

A/B by swapping the stock `.so` back in on the same panel was what proved it was
the patch and not Qt/FreeType/Plasma globally.

**Fix:** `renderType: Text.NativeRendering` on the task label in `Task.qml`.

**What does *not* work** (all tested, all stay subpixel):
- fontconfig `rgba=none` — the matched pattern is *already* `rgba: none`
- `opacity: 0.999`, `layer.enabled`, `clip` on the label or its parent
- `font.hintingPreference: PreferFullHinting`
- integer `pixelSize` / 0.75 pt steps that land on integer pixels
- building the font from `Kirigami.Theme.defaultFont` instead of overriding
  `font.family`/`font.pointSize`

QML exposes no `QFont::NoSubpixelAntialias` (`font.styleStrategy` does not exist
in QML and fails to load the component), and `Text.NativeRendering` is the only
QML-level switch that yields grayscale AA.

**Watch for:** if a future Qt/Kirigami version starts choosing grayscale for
`QtRendering` again, drop the `renderType` line to get smooth (non-hinted) glyphs
back — NativeRendering is slightly more jagged, which is the price of 10px text
being legible at all.
