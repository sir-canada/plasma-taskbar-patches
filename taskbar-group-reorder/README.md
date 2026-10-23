# taskbar-group-reorder

Patch for Plasma's **libtaskmanager** (plasma-workspace 6.7.2) that enables
**drag-reordering of window buttons within an inline task group**.

## The feature

With the Task Manager configured as **Sort: Manual + Group: By Program Name +
grouping shown inline** (`groupPopups=false` → `groupInline=true`), every window
of the same app is flattened into an inline cluster of buttons on the panel.

Stock libtaskmanager **refuses** any drag that starts and ends inside such a
cluster:

```cpp
// Disallow moves within a flattened-out group (TODO: for now, anyway).
if (groupingRowIndexParent.isValid() && (... == ...)) {
    return false;
}
```

This patch replaces that refusal with a **real intra-group reorder**: dragging
the middle button of your kitty cluster to the front now actually moves it.
Cross-cluster drags (moving the whole kitty cluster past the Firefox cluster)
and ungrouped moves are **unchanged** — an inline group is still relocated as one
atomic item when you drag it out of its own cluster.

The QML drag path in the Task Manager applet already called
`tasksModel.move(dragSource.index, insertAt)` correctly for this case; the block
was purely in C++ (`TasksModel::move()`), so no applet change is needed.

## Session-scoped caveat (by design)

The new order is **session-scoped**. Window-task order is *never* persisted by
upstream Plasma (only launchers/pinned items persist). The reorder lives only in
`TasksModel`'s in-memory sort map and is reset to insertion order when:

- **plasmashell restarts** (logout, upgrade, manual restart), or
- **the group's membership changes** — opening/closing a window of the same app
  triggers `consolidateManualSortMapForGroup()`, which re-imposes insertion
  order on that one group.

This is a deliberate, accepted limitation, not a bug. There is nowhere to persist
per-window order and no stable per-window identity across restarts.

## Runtime kill-switch (no rebuild to toggle)

The new code path is gated on an environment variable read **per call** to
`move()` (moves are rare, so per-call `qEnvironmentVariable` is fine):

| `PLASMA_INTRA_GROUP_MOVES` | Behaviour                                   |
|----------------------------|---------------------------------------------|
| unset / `1` (default)      | **ON** — intra-group reordering works       |
| `0`                        | **OFF** — historical refusal (`return false`) |

Because plasmashell inherits its environment from the systemd user session, set
it there and restart plasmashell:

```bash
# Disable the feature:
systemctl --user set-environment PLASMA_INTRA_GROUP_MOVES=0
systemctl --user restart plasma-plasmashell.service

# Re-enable (default):
systemctl --user unset-environment PLASMA_INTRA_GROUP_MOVES
systemctl --user restart plasma-plasmashell.service
```

For a persistent toggle across logins, use a drop-in instead:

```bash
mkdir -p ~/.config/environment.d
echo 'PLASMA_INTRA_GROUP_MOVES=0' > ~/.config/environment.d/99-intra-group-moves.conf
# then log out / back in, or: systemctl --user import-environment && restart plasmashell
```

No rebuild or reinstall is needed to flip the switch — only a plasmashell restart
so the process re-reads its environment.

## Invariant analysis — why the existing fixes are NOT regressed

`TasksModel::move()` carries three documented constraints
(bugs [444816](https://bugs.kde.org/444816),
[448912](https://bugs.kde.org/448912), commit `ea51795e`). The patch preserves
all of them because it **only adds a branch that is reached in exactly one new
situation — a child→child move inside one and the same inline group parent** —
and leaves every other path byte-for-byte identical:

- **Group contiguity** (`consolidateManualSortMapForGroup()` keeps a group's
  members contiguous in `sortedPreFilterRows`). The manual reorder does a single
  `sortedPreFilterRows.move(fromSort, toSort)` where **both** endpoints lie inside
  the group's already-contiguous run. `QList::move` only shifts the elements
  strictly between the two indices — all of which are members of that same run —
  so the run stays contiguous and **no other group's rows are touched**.
  Contiguity is preserved *by construction*, which is why the patch deliberately
  does **not** re-call `consolidateManualSortMapForGroup()` afterwards (doing so
  would re-impose insertion order and instantly undo the user's drag).

- **Cross-group / atomic-cluster moves** (the "treat flattened-out groups as
  single items" block, which is where bugs 444816 / 448912 / `ea51795e` live) is
  **entirely unmodified**. The stock refusal is kept verbatim for the
  kill-switch-off case and for the degenerate "target is the group parent
  itself" case; the new branch returns `true` before reaching any of that code.

- **Launcher-barrier logic** (separate-launchers, launch-in-place, launcher moved
  with its windows) lives *below* the flatten block and is only reached by the
  non-intra paths. Intra-group members are all the same app / same launcher, so
  reordering two windows of one app never involves launcher repositioning; the
  new branch returns before that tail runs.

**Known minor interaction (not a stock regression):** if you intra-reorder a
cluster and *then* drag that same (now-permuted) cluster across another cluster,
the unmodified cross-group code computes its move offsets from the group's
*insertion* order, so the cluster may land one slot off. It is **self-healing**:
the cross-group path re-runs `consolidateManualSortMapForGroup()` on both groups
at the end of the move, restoring a clean contiguous state, and the whole thing
resets on the next plasmashell restart anyway. This scenario did not exist before
the patch (intra-permuted inline groups were impossible), so it is a new
edge-case, not a regression of any pre-existing behaviour. Stock cross-group
drags (no prior intra-reorder) are byte-identical to upstream.

## Build / install (upgrade treadmill)

This is an **out-of-tree binary patch of a distro-owned library**
(`/usr/lib/libtaskmanager.so.6.7.2`, owned by the `plasma-workspace` package).
**Every `plasma-workspace` upgrade overwrites it**, silently reverting the
feature, and may also move the code the patch targets. After each upgrade:

```bash
./rebuild.sh          # re-downloads matching tarball, re-applies patch, rebuilds, reinstalls, restarts plasmashell
```

`rebuild.sh` fails loudly if `taskbar-group-reorder.patch` no longer applies to
the new source — port the patch (the target is the "Disallow moves within a
flattened-out group" block in `libtaskmanager/tasksmodel.cpp::TasksModel::move()`)
before reinstalling.

The `plasma-workspace-<ver>/build/` dir is kept for fast incremental rebuilds.

## Verification

The functional logic is proven by an autotest driven under a nested headless
KWin (`kwin_wayland --virtual`, `KWIN_WAYLAND_NO_PERMISSION_CHECKS=1`) so nothing
touches the live screen. See `verify/`:

- `tasksmodeltest-intragroup.patch` — the added `test_intraGroupMove()` case
  (SortManual + GroupApplications + groupInline, three same-app windows).
- `test-intragroup-output.txt` — three windows `[A,B,C]` form one inline group;
  **ON:** `move(mid→front)` returns `true`, order → `[B,A,C]`, still 3 contiguous
  rows (contiguity preserved). **OFF** (`PLASMA_INTRA_GROUP_MOVES=0`): `move`
  returns `false`, order unchanged.
- `test-fullsuite-output.txt` — the full `tasksmodeltest` suite (6/6 PASS),
  including the `test_moveBug444816` and `test_moveLauncherBug472524` regression
  guards, confirming cross-group / launcher-barrier behaviour is intact.

Real mouse-drag reordering on the live panel must be confirmed by hand — input
synthesis on Wayland was not used, and a standalone client cannot enumerate
windows because KWin denies the privileged PlasmaWindowManagement protocol to
non-shell clients (which is exactly why the autotest disables that check).

## Install manifest

Files replaced (stock backed up alongside with a `.stock` suffix):

| Installed file | Backup | Notes |
|---|---|---|
| `/usr/lib/libtaskmanager.so.<ver>` | `/usr/lib/taskbar-patches-backup/libtaskmanager.so.<ver>.stock` | the only file plasmashell dlopen()s for this logic |

> The backup deliberately does NOT live in `/usr/lib` with a lib-like name —
> ldconfig parses `libtaskmanager.so.6.7.2.stock` as a version candidate and
> re-points the `.so.6` symlink at it, silently reverting the patch.

To revert manually:

```bash
sudo cp -a /usr/lib/taskbar-patches-backup/libtaskmanager.so.<ver>.stock /usr/lib/libtaskmanager.so.<ver>
sudo ldconfig
systemctl --user restart plasma-plasmashell.service
```

(or simply reinstall: `sudo pacman -S plasma-workspace`)
