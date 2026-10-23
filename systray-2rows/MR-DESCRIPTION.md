# MR: System Tray — correct row math + "Very small" panel icon size option

Target: `plasma/plasma-workspace` `master`, branch `work/systray-very-small-icons`

## Title
`applets/systemtray: fix multi-row threshold and add "Very small" panel icon size option`

## Description

Two related changes to how the System Tray lays out icons in the panel:

**1. Correct the multi-row/column threshold math** (first commit)

`n` rows of icons occupy `n * iconSize + (n - 1) * spacing` — spacing only
exists *between* rows. The current formula divides by `(iconSize + spacing)`,
effectively demanding spacing after the last row too. In practice the second
row appears only at 52px of tray thickness instead of 48px (standard DPI,
22px icons). This is a small but user-visible off-by-one-spacing: panels
sized for two rows of 22px content (e.g. 48–51px) stay stuck at one sparse
row.

**2. Add a "Very small" option to the existing "Panel icon size" setting** (second commit)

Users who run thick panels with a two-row Task Manager (40–56px) frequently
ask for smaller/denser tray icons — the tray is the only panel widget that
can't be made more compact today. This adds a third choice to the existing
combobox (`Very small` / `Small` / `Scale with Panel height`), backed by a new
`useVerySmallIcons` bool (default **off**, no behavior change unless opted
in). When enabled, panel tray icons cap at `iconSizes.small` (16px) instead
of `smallMedium` (22px), which together with the fixed threshold allows two
rows on a ~40px tray area (e.g. a 44px panel with standard margins:
36px usable = 2×16 + 4).

The hidden-items popup is unaffected; `scaleIconsToFit` behavior is
unchanged; vertical panels benefit symmetrically (columns).

## Screenshots
(TODO before submitting: attach)
- Before: 44px panel, single row of 22px icons
- After: 44px panel, `Very small` enabled — two rows of 16px icons
- Settings dialog showing the three-way combobox

## Test plan
- Built and ran on Plasma 6.7.2 (backport) and master.
- Toggle off → identical to current behavior (default).
- Toggle on, 44px horizontal panel → two rows; popup, clicking, highlight OK.

## Submission steps (manual, needs KDE Invent account)
1. Create account at https://invent.kde.org (KDE Identity).
2. Fork `plasma/plasma-workspace` via the web UI.
3. `git remote add fork git@invent.kde.org:<username>/plasma-workspace.git`
   (or https remote with token)
4. `git push fork work/systray-very-small-icons`
5. Open MR against `plasma/plasma-workspace` `master`; paste this description;
   attach screenshots; label `NEEDS REVIEW`. Relevant longstanding wishes:
   search bugs.kde.org for "system tray icon size" (e.g. bug 356446) and link
   any that match.
