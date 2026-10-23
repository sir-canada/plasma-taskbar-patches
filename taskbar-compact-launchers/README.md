# taskbar-compact-launchers

Patch for the Plasma 6 **Task Manager** applet (`org.kde.plasma.taskmanager`)
so that on a **multi-row horizontal panel** the pinned launchers stack
`R`-per-column in narrow, row-height-wide columns at the start of the bar
instead of each launcher stretching to a full task-button width.

Tested on plasma-desktop **6.7.2-1.1** (CachyOS/Arch), horizontal 44px panel,
Task Manager config `maxStripes=2`, `forceStripes=true`, `separateLaunchers=true`.

## The problem

With `forceStripes` on a horizontal panel the applet lays its items out in a
`GridLayout` filled row-major. Launchers come first (because `separateLaunchers`
orders them at the front); each leading launcher lands in the top row and
*shares its column with a bottom-row task*, so the launcher column is stretched
to the task's width. Result: fat, wasteful launcher columns.

## The fix

`Task.qml` gives every delegate an explicit `Layout.row` / `Layout.column`, but
only in the gated case:

* horizontal panel (not vertical)
* not icons-only (`org.kde.plasma.icontasks`)
* effective row count `R = taskList.rows > 1`
* not inside a group popup (`!inPopup`)

Outside the gate both bindings evaluate to `-1`, which restores stock
`GridLayout` auto-placement (byte-identical behavior).

Inside the gate, with `L` = visible launcher count, `T` = visible task count,
`R` = rows:

* **launcher** with launcher-index `i` (`= index`, launchers are contiguous at
  the front): `row = i % R`, `column = floor(i / R)`.
* **task** with task-index `j = index - L`: `taskCols = ceil(T / R)`,
  `startCol = ceil(L / R)`, `row = floor(j / taskCols)`,
  `column = startCol + (j % taskCols)`.

If `L % R != 0` the last launcher column is left partially empty; tasks still
begin at `startCol`. Launchers keep their existing width cap
(`height / rows`, square), so a launcher-only column ends up ~row-height wide.

`L` is `TaskList.launcherCount`, a plain `int` that each `Task` delegate keeps
up to date by **registering itself** with the list. `TasksModel.launcherCount`
is not used (it counts *configured* launchers and does not drop when a launcher
is hidden because its app is running). A parent-side scan such as
`children.reduce(... child.model.IsLauncher ...)` is **not** used either: reading
another delegate's `model`/role in a parent binding creates no dependency, so it
never re-evaluates and latches at the `L = 0` degenerate case right after a quiet
`plasmashell` restart (the layout then renders launchers row-major full-width).

Instead each delegate exposes

```qml
readonly property bool countsAsLauncher: !inPopup && visible && !!model && model.IsLauncher
```

— every term is a notifiable property (`inPopup`, `visible`, `model`, and the
`model.IsLauncher` role, which *does* track inside its own delegate). On any
change, on `Component.onCompleted`, and on `Component.onDestruction` the delegate
adds or removes itself from `TaskList.launcherCount` (idempotent, guarded by a
`launcherRegistered` flag). No timers, polling, or `Qt.callLater`. Opening or
closing a pinned app (launcher row removed/inserted) therefore repacks the
launcher columns immediately, and the count is correct on the very first frame
after a restart because it is built from per-delegate signals, not a lazy scan.

## Files

* `taskbar-compact-launchers.patch` — the QML diff (`Task.qml`, `TaskList.qml`,
  `MouseHandler.qml`, `PulseAudio.qml`), `-p1`.
* `rebuild.sh` — re-download source, apply patch, build only the applet, back up
  and install the plugin, restart plasmashell. Re-run after a plasma-desktop upgrade.
* `taskbar-compact.conf.example` — annotated runtime-config example for
  `~/.config/taskbar-compact.conf`.
* `gui/` — **settings GUI** (`taskbar-compact-settings`, PySide6). Edit every
  runtime key from a window instead of hand-editing the INI; handles the
  stop-plasmashell/write/restart sequence for you. Install:
  `gui/install-gui.sh` (needs `pyside6`).
* The stock plugin is backed up in place as `<plugin>.so.stock` on first install.

## Build / install

```sh
./rebuild.sh
```

It builds `org.kde.plasma.taskmanager` from the matching plasma-desktop tarball
and installs to
`/usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.taskmanager.so`
(stock backed up to `…so.stock` the first time). The full plasma-desktop tree is
trimmed to just the taskmanager applet so unrelated optional build deps
(kcm_touchpad/mouse X11, attica-kde, …) are not required.

## Uninstall / revert

```sh
sudo cp /usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.taskmanager.so.stock \
        /usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.taskmanager.so
systemctl --user restart plasma-plasmashell.service
```

## Label indicator strip (Feature 1)

The task-button label (main list and group-popup list) has a leading Claude Code
status indicator stripped from the *displayed* text only (`Task.displayText`):
a glyph matching `/^[✳✻✶✽✢·⠀-⣿]\s+/` — the asterisk family `{✳ ✻ ✶ ✽ ✢}`
(U+2733, U+273B, U+2736, U+273D, U+2722); `·` (U+00B7); and the whole
Braille Patterns block U+2800–U+28FF (`⠀`–`⣿`) — followed by whitespace. Tooltips,
the model, and Accessible text keep the raw title. ASCII `*` is intentionally not
stripped (editors use it for unsaved markers).

**Current Claude Code semantics (verified live via KWin caption logging):** the
prefix is the *inverse* of an earlier assumption. An **animated Braille spinner**
glyph (U+2800–U+28FF, e.g. `⠂ title` ↔ `⠐ title` alternating ~1/s) = **working /
busy**; `✳ ` (and the rest of the asterisk family) = **idle / done**. Both are
stripped for display; the strip class covers both so the label text is clean in
either state. The busy/idle distinction drives Feature 2.

## Smaller task label font

The task-button label font **defaults** to `0.65 ×` the theme default point
size, clamped to a hard `6pt` floor
(`font.pointSize: Math.max(6, defaultFont.pointSize * 0.65)`; null-safe if
`Kirigami.Theme.defaultFont` is unavailable). The clamp is a fixed 6pt rather
than `Kirigami.Theme.smallestFont` (8pt here), which rendered too tall.
Fractional point sizes are kept as-is. Both the label **family and size** are
overridable at runtime without a rebuild — see [Runtime config](#runtime-config-taskbar-compactconf).

The horizontal gap between the task icon and the title label (the label
`anchors.leftMargin` term `TaskManagerApplet.LayoutMetrics.labelMargin`, which is
`Kirigami.Units.smallSpacing`) is halved to `Math.max(2, Math.floor(labelMargin / 2))`
so the title sits tighter against the icon. Only that one term changes — outer
button padding (`taskFrame.margins`) and the label→audio-icon gap are untouched.

## Claude Code state visuals (Feature 2)

Visuals driven by the busy/idle title prefix (see semantics note above).
`task.stateWorking` is `true` while the title matches `/^[⠀-⣿]\s/` (a Braille
spinner + whitespace = Claude busy); the done/attention **latch**
(`task.attentionPending`) is set when a delegate's title transitions *from*
Braille (working) *to* non-Braille (done) while it is **not** the active window,
and cleared when the window is activated (`onIsActiveWindowChanged`). Group
parents are skipped for the latch (`!model.IsGroupParent`).

The visuals are **freely mixable and switchable at runtime** (no rebuild) via
two keys in `taskbar-compact.conf` (see
[Runtime config](#runtime-config-taskbar-compactconf)):

* **`workingVisual`** — a **comma-separated list** (any combination) of the
  working visuals below; drawn while `stateWorking`.
* **`attentionVisual`** — **one** of the attention visuals below; drawn while the
  latch is set (or the window demands attention).

| Token | `workingVisual` (while busy) | `attentionVisual` (latched/done) |
| --- | --- | --- |
| `icon-pulse` (S6) | app **icon** opacity pulses `1.0 ↔ pulseDim` | — (working only) |
| `tint-pulse` (S1) | whole button breathes a faint fill, alpha `0.05 ↔ 0.16` | — (working only) |
| `underline` (S2) | 2px bottom bar (inset 3px L/R), opacity pulses `0.25 ↔ 1.0` | steady 2px orange bottom bar |
| `edge-bar` (S4) | 3px left-edge bar (inset 2px T/B), opacity pulses `0.3 ↔ 1.0` | steady orange left bar **+ faint orange wash @0.15** |
| `bevel` (S3) | raised 3D bevel, brightness breathes | steady raised **orange** bevel |
| `fill` | — (attention only) | steady flat orange fill (`neutralTextColor` @0.35) |
| `flash` (S5) | — (attention only) | **flashing** orange fill, hard square wave `0.40 ↔ 0.05`, period `flashPeriodMs` |
| `two-stage` (S7) | — (attention only) | **decelerating intro** tint pulse for `attentionIntroMs`, then an infinite **subtle latch** pulse `0.27 ↔ 0.42`, period `attentionLatchPeriodMs` |
| `none` | nothing | nothing |

All motion rides one **shared per-task cosine phase** `f = 0.5 − 0.5·cos(2π·phase)`
(rises `0 → 1 → 0` once per `pulsePeriodMs`), stepped by a per-task `Timer`
(`iconPulseTimer`) advancing an integer `pulsePhaseStep` over `[0, pulseSteps)`
(interval = `pulsePeriodMs / pulseSteps`). A `Timer` is used rather than a QML
`Animation` because this desktop has KDE animations globally disabled
(`AnimationDurationFactor=0`), which collapses `Animation`/`Behavior` durations
to 0. Working-fill/bar visuals are lightweight `Rectangle`s anchored to `frame`
(z-order: tint fill lowest, then bevel, then bars/underline, all below
icon/label); the icon-pulse opacity binds directly on the `Kirigami.Icon` (not
the `iconBox` `Loader`, whose `opacity` binding does not re-evaluate reliably).
`pulseSteps = 2` reproduces the old 2-state blink; higher = smoother.

The **S5 flash** uses a *second* per-task phase (`flashPhaseStep` over a fixed 20
ticks per `flashPeriodMs`) so its ~45/55-duty **hard** square wave is independent
of the smooth working cosine.

The **S7 two-stage** attention visual has its own per-task driver
(`twoStageTimer`, fixed 50 ms tick; elapsed time is a `Date.now()` delta from
the moment attention began, so tick jitter cannot drift the curve). Stage 1
(intro, `attentionIntroMs`; `0` = skip): a whole-button *decelerating* tint
pulse from a **hardcoded** keyframe table (fraction → alpha, cosine
ease-in-out between adjacent points). The table always occupies the **final
5 s of the intro in real time** (the approved ~1 s pulse pacing never
stretches); when `attentionIntroMs > 5000` the first `attentionIntroMs − 5000`
ms are a **lead-in** of full-depth 1 s cosine pulses (`0.12 ↔ 0.55`) whose
phase is anchored backwards from the lead-in end, so it always lands exactly
on `0.12` falling into the table's `0.12` start — seamless for any intro
length, not just multiples of 1000. `attentionIntroMs ≤ 5000` compresses the
table over the whole intro. Stage 2 (latch, infinite): subtle cosine
pulse `0.27 ↔ 0.42` per `attentionLatchPeriodMs`, phase 0 at latch start — the
intro table ends at `0.27` rising, so the stage handoff is seamless. The alpha
is painted by `stateFill` over the attention base colour; `stateFill`'s ~100 ms
opacity/colour `Behavior`s are **disabled while two-stage paints** (a 100 ms
`NumberAnimation` retargeted every 50 ms would forever lag the curve). Latch
semantics are identical to the other attention visuals: activating the window
clears it, even mid-intro.

### Base colors

Every working visual defaults to the theme **highlightColor** and every
attention visual to the theme **neutralTextColor** (orange). Two optional keys
override those base colors (alphas/curves unchanged):

* **`workingColor`** — base color for **all** working visuals (`tint-pulse` fill,
  `underline`, `edge-bar`, and the `bevel` breathe tint). `icon-pulse` is
  opacity-only and is **unaffected**. The `bevel` keeps its raised **white**
  look unless `workingColor` is set. Empty = theme highlightColor.
* **`attentionColor`** — base color for **all** attention visuals. Empty = theme
  neutralTextColor.

Any string QML's color parser accepts (`#RRGGBB`, named colors like `magenta`).
An empty or unparseable value falls back to the theme color (a bad value can
never break the buttons): `Qt.color(str)` maps an unparseable string to invalid
`#000000`, treated as the fallback unless the user explicitly asked for black.

### Timer gating

The pulse, flash and two-stage `Timer`s are **imperatively gated**: they start
`running: false` and are only `start()`ed/`stop()`ed from `onPulseActiveChanged`
/ `onFlashActiveChanged` / `onTwoStageActiveChanged` (plus an initial check in
`Component.onCompleted`), where
`pulseActive = stateWorking && <an animated working visual is selected>`,
`flashActive = stateAttention && attentionVisual == flash` and
`twoStageActive = stateAttention && attentionVisual == two-stage`. An **idle taskbar
therefore runs zero phase timers** (≈30 delegates would otherwise each tick a
timer forever). A declarative `running: <property>` binding was found not to
reliably auto-start the `Timer` on this platform, but explicit `start()` from
the change handler is reliable.

### `stateFill` suppression

The flat state fill (`stateFill`, which also draws active/hover) paints its flat
**orange** only when `attentionVisual == fill` (or the Timer-stepped two-stage
alpha when `two-stage`); for every other attention visual
it falls through to the active/hover/none look so the chosen visual paints alone
(no double-up). Idle/active/hover/marquee/launchers and the geometry-anchored
overlays (progress, audio) are untouched — the `FrameSvgItem` stays `opacity: 0`.

### Legacy `claudeStyle` alias

`claudeStyle` (`icon-pulse` | `bevel` | `both`) is a **legacy alias**. When
`workingVisual` / `attentionVisual` are **absent (empty)**, their values are
**derived** from `claudeStyle`; when the new keys are present, they win.

| `claudeStyle` | ⇒ `workingVisual` | ⇒ `attentionVisual` |
| --- | --- | --- |
| `icon-pulse` (default) | `icon-pulse` | `fill` |
| `bevel` | `bevel` | `bevel` |
| `both` | `bevel,icon-pulse` | `bevel` |

## Windows-style flat task-button visuals (Feature 3)

The stock stateful `tasks.svg` frame background (the `normal` / `active` /
`minimized` / `attention` / `focus` prefixes on the per-task `KSvg.FrameSvgItem`
`frame`) is replaced by a flat, Windows-style look driven by a single Rectangle
(`stateFill`) that follows the color scheme through `Kirigami.Theme` colors.
There is **no underline** on any state.

The `frame` item is **kept** but set to `opacity: 0` (not `visible: false`,
which would disable its `DragHandler` child and the `anchors.fill: frame` /
`frame.*` geometry references used by the progress overlay and the audio-stream
indicator). Label/icon insets are unaffected because they derive from the
separate hidden `taskFrame` in `main.qml` (fixed `normal` prefix), not from the
per-task `frame`. The `frame` is retained purely for geometry: `stateFill`
anchors to it (`anchors.fill: frame`), inheriting its multi-row `iconMargin`
inset region.

State drivers (`stateHovered`, `stateActive`, `stateLauncher`, `stateAttention`)
are readonly properties on `task`; `stateFill` alone renders every state:

* **Running, not active / minimized:** no fill (opacity 0).
* **Active:** `stateFill` = `highlightColor` @0.20 (0.28 if also hovered),
  `radius: 3`, behind the icon/label.
* **Hover (not active):** `stateFill` = `textColor` @0.08.
* **Attention / work-done latch:** `stateFill` = `neutralTextColor` @0.35, steady.
  `stateAttention` includes `task.attentionPending` (see Feature 2), so a delegate
  that finished work while unfocused shows a persistent orange fill until it is
  activated. No animation — the old `flashAnimation` / `task.flashing` are gone.
* **Group parents:** treated as a normal task — `stateActive` is `model.IsActive`
  (already true when a grouped child is active), otherwise running style.
* **Launchers** (`model.IsLauncher`): icon only — the only fill is the hover fill
  (`textColor` @0.08).

`stateFill` has a `Behavior` on `opacity` and `color` (~100ms) for smoothness.
The stock `states` array still sets `frame.basePrefix` but that only drives the
now-invisible frame.

### Single-line hard-clipped titles

In our gated case (`task.explicitPlacement`: horizontal panel, `>1` row, not
icons-only, not a group popup) the task label is forced onto a single line and
hard-clipped flush at the button edge, with **no** `…` ellipsis and no vertical
wrapping/chopping. The property combination on the label
(`readonly property bool flatClipLabel: task.explicitPlacement`) is:
`wrapMode: flatClipLabel ? Text.NoWrap : …`, `elide: flatClipLabel ?
Text.ElideNone : Text.ElideRight`, and `maximumLineCount: flatClipLabel ? 1 :
(Plasmoid.configuration.maxTextLines || undefined)`.

The label is wrapped in a **clipping `Item`** (`labelClip`) that takes over the
label's exact anchored region (icon + margins) and sets `clip: true`. The
wrapper is anchor-managed (`anchors.fill: parent`), so it is always sized by the
button and can never collapse to the child's `implicitWidth` — a
Layout-collapsed wrapper would report `implicitWidth 0` and make **all titles
vanish silently** with no QML error. Inside the wrapper the label free-runs at
`width: implicitWidth` (its full text width, `ElideNone`) so it can be scrolled;
the wrapper clips the overflow. Everywhere else (vertical panels, icons-only,
group popups) the label fills the wrapper and stock wrap/elide behavior is kept.

**Hover marquee.** When the button is hovered (`task.highlighted`) and the
single-line title overflows the clip region (`label.clipped`), a
`SequentialAnimation` (loops infinitely) scrolls `label.x`: wait `marqueeDelayMs`
ms (default 400; `0` = start scrolling the instant the pointer hovers), scroll
left at `marqueeSpeed` px/s (default 60; `duration = overflowPx / speed × 1000`,
linear) until the text end is flush with the right edge, hold 800 ms, snap back
to `x 0`, pause 600 ms, repeat. Only the *start-delay* `PauseAnimation` is
parameterized (`duration: label.marqueeDelay`, clamped `0..5000`); the scroll
mechanics are untouched. It touches only `label.x` — never a layout width — so it
cannot feed back into sizing. On hover exit the animation stops and `x` snaps to
`0` instantly (`onRunningChanged`). Short (non-overflowing) titles never move.
Speed and start delay are [configurable](#runtime-config-taskbar-compactconf).

## Runtime config (`taskbar-compact.conf`)

> **Prefer the GUI:** `gui/taskbar-compact-settings` edits every key below
> from a window, shows the built-in defaults, and safely stops/restarts
> plasmashell around the write (see the QSettings warning further down for why
> that matters). The rest of this section documents the raw file format.

A few label/marquee knobs are overridable **without a rebuild** via an optional
file at `~/.config/taskbar-compact.conf`. `TaskList.qml` reads it **once** at
component load with a QtCore `Settings` element (`import QtCore`;
`location: StandardPaths.writableLocation(GenericConfigLocation) +
"/taskbar-compact.conf"`), i.e. `QSettings` in INI format. There is **no
watcher** — restart plasmashell (`systemctl --user restart
plasma-plasmashell.service`) to apply changes.

> A synchronous `XMLHttpRequest` `file://` GET is **not** used: Qt 6 disables
> local-file XHR by default (`QML_XHR_ALLOW_FILE_READ=1` would be required in the
> plasmashell process environment), which silently blanked the override.

Format: INI, in the default `[General]` group:

```ini
[General]
fontFamily=DejaVu Sans
fontPointSize=7.5
marqueeSpeed=60
marqueeDelayMs=400
workingVisual=icon-pulse
attentionVisual=fill
flashPeriodMs=2400
pulsePeriodMs=2400
pulseDim=0.45
pulseSteps=32
bevelBreathe=true
```

All keys are optional; a missing file or missing key falls back to the default. A
present-but-empty `fontFamily`, a non-positive number, an unrecognised token, or
an unparseable colour is ignored in `Task.qml` (falls back to its default), so a
malformed value can never blank the task buttons.

> **`QSettings` owns the file's format.** Because it is a `QSettings` store,
> plasmashell **rewrites/normalizes** the file on exit *and on start*: it prepends
> the `[General]` header, **sorts keys alphabetically**, and writes back any
> default key that was missing (`claudeStyle`, `workingColor=`, `attentionColor=`,
> …). **Comments are not preserved** — `QSettings` does not treat `#` lines as
> comments. Edit the file **only while plasmashell is stopped**
> (`systemctl --user stop plasma-plasmashell.service`, edit, `start`), otherwise a
> live instance clobbers your edit on exit.
>
> **Comma caveat.** `workingVisual`, `workingColor` and `attentionColor` are
> read as `var`: `QSettings` parses an *unquoted* comma value
> (`workingVisual=underline,icon-pulse`, or an `rgb(…)` colour) as a list, so the
> applet re-joins it with `,` (and trims each token). Write the value plainly,
> unquoted. When hand-editing a *fresh* file, write only the keys you want to
> change from default; let plasmashell normalize the rest on first start (writing
> every default numeric key at once can lose a non-default `pulsePeriodMs` /
> `pulseSteps` to a startup read/write race — the normalized file that plasmashell
> produces is then stable across restarts).

| Key | Default | Meaning |
| --- | --- | --- |
| `fontFamily` | theme font family | Task-button label font family. |
| `fontPointSize` | `Math.max(6, defaultFont.pointSize × 0.65)` | Task-button label point size. Doubles as the **minimum** (and the `TextMetrics` measuring size) when the adaptive sizing below is enabled. |
| `fontPointSizeMax` | `0` | **Adaptive label sizing** upper bound, pt. `0`/absent or ≤ the effective minimum (`fontPointSize` or its computed default) = feature **disabled** — labels behave exactly as before. When enabled, the flat multi-row label size auto-floats between the minimum and this max: each task reports the point size at which its full title would exactly fit its clip (measured at the *minimum* size, so the applied size can never feed back), the sizes are aggregated, quantized down to `fontAutoStepPt`, and applied to all main-list labels. With many truncating windows the aggregate sits at the minimum **by design** — the max only engages when the bar is sparse and/or titles fit their buttons. |
| `fontAutoStepPt` | `0.5` | Adaptive-size quantization step, pt (floor, anchored at the minimum). Non-positive → `0.5`. |
| `fontAutoDebounceMs` | `500` | Debounce before re-aggregating after a fit change, ms. `0` = apply immediately. Clamped `0..10000`. |
| `fontAutoAggregate` | `mean` | Aggregation over the per-task ideal sizes: `mean` or `min`. With `min`, any single truncating title pins the applied size at the minimum. Anything else → `mean`. |
| `fontAutoHysteresisPt` | `0` | Adaptive-size **hysteresis**, pt: a recomputed (quantized, clamped) candidate size only replaces the currently applied size when it differs by at least this much, so small aggregate drift (a title change, ±1 window near a quantize boundary) can't make the size hop. An applied size left outside the configured `[min, max]` by a runtime bounds change is always replaced. `0` = apply every change (pre-hysteresis behavior). |
| `wheelVolume` | `false` | `true` = the mouse wheel **anywhere over the taskbar** changes the **system (default sink) volume** through plasma-pa's `GlobalService` — same step, bounds, OSD and audible feedback as scrolling the tray volume icon; <kbd>Shift</kbd>+wheel = fine step. Bypasses the stock `wheelEnabled` applet modes (task cycling / per-app stream volume) and keeps the wheel handler active even with the stock behavior set to *no action*. Routed through the applet's optional plasma-pa loader, so a system without plasma-pa degrades to a no-op. |
| `marqueeSpeed` | `60` | Hover-marquee scroll speed, px/s. |
| `marqueeDelayMs` | `400` | Hover-marquee start delay before scrolling begins, ms. `0` = scrolling starts the instant the pointer hovers. Clamped `0..5000`. |
| `workingVisual` | *(from `claudeStyle`)* | **Comma list** of working visuals: `icon-pulse`, `tint-pulse`, `underline`, `bevel`, `edge-bar`, `none`. See [Feature 2](#claude-code-state-visuals-feature-2). |
| `attentionVisual` | *(from `claudeStyle`)* | **One** attention visual: `fill`, `flash`, `two-stage`, `underline`, `bevel`, `edge-bar`, `none`. |
| `workingColor` | theme highlightColor | Base colour for all working visuals (`icon-pulse` unaffected; `bevel` stays white unless set). `#RRGGBB`/named; empty/invalid → theme. |
| `attentionColor` | theme neutralTextColor | Base colour for all attention visuals. `#RRGGBB`/named; empty/invalid → theme. |
| `flashPeriodMs` | `2400` | Full S5 attention-flash square-wave cycle, ms. |
| `attentionIntroMs` | `5000` | S7 two-stage attention intro (stage 1) duration, ms. The decel keyframe table occupies the **final 5 s**; longer intros prepend full-depth 1 s pulses as a lead-in. `0` = **skip the intro** (straight to the latch pulse). Clamped `0..60000`. |
| `attentionLatchPeriodMs` | `3000` | S7 two-stage attention latch (stage 2) pulse cycle, ms. Clamped `200..60000`. |
| `fillRadius` | `3` | Corner radius (px) of the flat button fills (`stateFill`, `washFill`, S3 bevel background). `0` = square corners. The 2px/3px underline/edge-bar bars are unaffected. Clamped `0..10`. |
| `claudeStyle` | `icon-pulse` | **Legacy alias** (`icon-pulse`/`bevel`/`both`); only used to derive `workingVisual`/`attentionVisual` when those are absent. |
| `pulsePeriodMs` | `1600` | Full working-pulse/breathe cosine cycle, ms (Timer interval = `pulsePeriodMs / pulseSteps`). |
| `pulseDim` | `0.45` | Icon-pulse dim opacity (`0 < d < 1`). |
| `pulseSteps` | `16` | Ticks per pulse cycle for the smooth cosine waveform. Higher = smoother; `2` = old 2-state blink. Clamped `2..60`. |
| `bevelBreathe` | `true` | Whether the `bevel` working brightness breathes with the pulse phase. `false` = statically raised. |

Only positive numeric values are accepted for `fontPointSize` / `marqueeSpeed` /
`pulsePeriodMs` / `flashPeriodMs`; `marqueeDelayMs` is clamped to `0..5000` (`0`
is valid — instant start); `pulseDim` must be strictly between 0 and 1;
`pulseSteps` is rounded and clamped to `2..60`; `attentionIntroMs` is rounded
and clamped to `0..60000` (`0` is valid — skip the intro); `attentionLatchPeriodMs`
is rounded and clamped to `200..60000`; `fillRadius` is clamped to `0..10`
(`0` is valid — square corners; negative/missing → 3); `bevelBreathe` is a boolean;
`claudeStyle` must be one of `icon-pulse` / `bevel` / `both`; a non-empty string
is required for `fontFamily`; `fontPointSizeMax` ≤ the effective minimum disables
adaptive sizing (`0` is the off default); `fontAutoStepPt` must be positive
(else `0.5`); `fontAutoDebounceMs` is clamped to `0..10000` (`0` is valid —
immediate); `fontAutoAggregate` must be `mean` or `min` (else `mean`);
`fontAutoHysteresisPt` is floored at `0`; `wheelVolume` is a boolean.

> On this system the file is set to `DejaVu Sans` / `7.5pt`,
> `workingVisual=icon-pulse`, `attentionVisual=fill` (the S6 smooth icon glow +
> steady orange done-fill), `pulsePeriodMs=2400` / `pulseSteps=32` (a slower, more
> gradual glow), `flashPeriodMs=2400`, `bevelBreathe=true`, `marqueeSpeed=50`,
> `marqueeDelayMs=0` (marquee starts scrolling instantly on hover), and
> `workingColor`/`attentionColor` empty (theme colours). It uses `DejaVu Sans`
> because **`DejaVu LGC Sans` is not installed** here; if you install the LGC
> variant, change `fontFamily=DejaVu LGC Sans`. The file is user data — neither
> `rebuild.sh` nor the applet creates or modifies it.

## Notes

* `TaskList.qml` overrides the `columns` hint in the gated case to
  `ceil(L/R) + max(1, ceil(T/R))` — the exact column count the split placement
  in `Task.qml` uses. The stock `ceil(count/R)` is one column short whenever
  both `L` and `T` are odd, and Qt does NOT merely warn about
  `Layout: column (N) should be less than the number of columns (N)` — it
  **rejects the explicit position and auto-places the item**, which made the
  last task render on top of a neighbour (fixed 2026-07-12; earlier revision
  of this note wrongly called the warning harmless). Verified empirically with
  a standalone GridLayout test.

## Gotcha: `QT_PLUGIN_PATH` shadowing (incident write-up)
If the patch "doesn't take" after a successful install, check for plugin-path
shadowing. On the original machine a `plasma-plasmashell` systemd **user**
drop-in set
`Environment=QT_PLUGIN_PATH=%h/.local/lib/qt6-plugin-override`. Qt searches that
directory **before** the system plugin path, and it held a *stock*
`org.kde.plasma.taskmanager.so`, so every `/usr/lib` install by `rebuild.sh` was
silently shadowed and the panel reverted to stock behaviour (full-width
launchers, `✳` prefixes, default font). This was **not** a source-tree edit — the
extracted tree still matched the committed patch byte-for-byte. Fix: removed the
drop-in and the `~/.local/lib/qt6-plugin-override` tree, ran
`systemctl --user daemon-reload`, restarted plasmashell; `/usr/lib` is canonical
again. The shadow `.so` and the clobbering build are kept untracked in the
workdir for reference.
