# plasma-taskbar-patches

Source patches for the KDE **Plasma 6** panel that make a horizontal multi-row
taskbar actually pleasant: compact pinned launchers, flat Windows-style task
buttons with a hover marquee, busy/done state visuals for terminal AI agents
(Claude Code), adaptive label fonts, wheel-volume, drag-reordering of grouped
window buttons, and a two-row 16px system tray with drag-to-reorder icons.

Developed and tested on CachyOS/Arch, Plasma **6.7.x and 6.8.0**, Wayland, 44px
horizontal panel. The rebuild scripts assume a pacman-based distro (they read
the installed version with `pacman -Q`); on other distros, set the version by
hand and adapt the install paths.

## The three patches

| Directory | Patches | What you get |
|---|---|---|
| [`taskbar-compact-launchers/`](taskbar-compact-launchers/) | Task Manager applet (plasma-desktop) | Pinned launchers packed N-per-column at row height; flat Windows-style buttons; single-line hard-clipped titles + hover marquee; smaller/adaptive label font; Claude Code busy/done visuals (9 styles, runtime-switchable); mouse-wheel volume; ~25-key runtime config file, no rebuild needed |
| [`taskbar-group-reorder/`](taskbar-group-reorder/) | libtaskmanager (plasma-workspace) | Drag-reorder window buttons *within* an inline task group (stock refuses); env-var kill switch; regression-tested against upstream move-logic bugs |
| [`systray-2rows/`](systray-2rows/) | System Tray applet (plasma-workspace) | 2 rows on a 44px panel (corrected row threshold); new "Very small" 16px icon option; drag-to-reorder tray icons, persisted |

Each directory is self-contained: the patch(es), a `rebuild.sh` that downloads
the matching KDE source tarball, applies, builds *only* the needed target, and
installs, plus a README with full design notes.

## Install

```sh
cd taskbar-compact-launchers && ./rebuild.sh    # taskbar
cd ../taskbar-group-reorder  && ./rebuild.sh    # inline-group drag reorder
cd ../systray-2rows          && ./rebuild.sh    # tray
```

Build deps: `base-devel`, `cmake`, `ninja`, Qt6 + KF6 dev headers (on Arch
these come with the KDE dev groups). Each script backs up the stock binary
before installing and fails loudly if a patch no longer applies.

## ⚠️ The upgrade treadmill

These are out-of-tree patches to **pacman-owned files**. Every
`plasma-desktop` / `plasma-workspace` upgrade silently reverts them.

**On this machine this is now automatic** — a pacman hook schedules
[`auto/plasma-patches-rebuild.service`](auto/), which rebuilds and reinstalls
after pacman exits, and also runs at boot to catch aborted upgrades. See
*Automatic re-apply* below.

The manual path still exists and still works:
**after each Plasma upgrade, re-run the `rebuild.sh` scripts** (or the
one-shot [`reapply-all.sh`](reapply-all.sh), which runs all three in order).
If a patch no longer applies, the upstream code moved — port the patch first
(each README names the exact target code). Rebase history, per Plasma version:
[`PORTS.md`](PORTS.md) (latest: 6.8.0, one hunk of the taskbar patch).

### Automatic upgrade reminder (pacman hook)

`packaging/plasma-taskbar-patches.hook` fires on every upgrade of
`plasma-workspace` **or** `plasma-desktop` and prints a loud PostTransaction
reminder to run `reapply-all.sh`. It is a **reminder, not an auto-compile** —
building three KDE targets and restarting plasmashell *inside* a pacman
transaction is unsafe (blocks pacman, restarts the shell mid-upgrade), so the
actual rebuild stays a deliberate one-command follow-up:

```sh
~/Documents/projects/plasma-taskbar-patches/reapply-all.sh
```

Install the hook:

```sh
sudo install -m644 packaging/plasma-taskbar-patches.hook \
  /etc/pacman.d/hooks/plasma-taskbar-patches.hook
```

> **The hook actually installed on this machine is not this one.** Since
> 2026-10-20 it is `auto/plasma-taskbar-patches.hook`, which schedules the
> unattended rebuild described below. A reminder alone was not enough: it only
> helps if you read it, and it only fires if PostTransaction runs at all.
> `packaging/` keeps the reminder-only version as the repo default.

> History: a prior `systray-2rows.hook` covered only `plasma-workspace` and
> pointed at a stale pre-reorg path (`~/Documents/systray-2rows/`). It was
> replaced by this unified hook (both packages, correct `reapply-all.sh` path).
> **The lib patch was built against 6.7.2; the 6.7.2→6.7.3 upgrade is exactly
> what reverted the intra-group drag reorder** — the reason this hook exists.

### Automatic re-apply (installed on this machine, 2026-10-20)

The reminder hook above depends on PostTransaction actually running, which is
not guaranteed: on 2026-10-20 the 6.8.0 transaction died mid-extraction, no hook
of any kind ran, and the patches sat reverted unnoticed. This bundle closes that
hole by doing the rebuild unattended, after pacman has exited:

| File | Installs to | Role |
|---|---|---|
| `auto/plasma-patches-auto.sh` | `/usr/local/sbin/plasma-patches-auto` | workers: verify markers, build as user, install as root, restart plasmashell |
| `auto/plasma-patches-rebuild.service` | `/etc/systemd/system/` | oneshot unit, started by the hook **and** on every boot |
| `auto/plasma-taskbar-patches.hook` | `/etc/pacman.d/hooks/` | replaces the reminder-only hook; just `systemctl start --no-block` |

Why it is shaped that way: nothing heavy happens *inside* the pacman
transaction (pacman would block and the shell would restart mid-upgrade). The
hook only schedules the oneshot; the unit waits for `/var/lib/pacman/db.lck` to
clear, builds as the repo owner (so no interactive sudo password), then installs
on new inodes as root. The boot run is what catches an aborted upgrade, and it
exits in milliseconds when the markers are already present.

Fail-safe: a patch that no longer applies aborts **before** anything is
installed — the stock binaries stay in place and a desktop notification asks for
a port. Log: `/var/log/plasma-patches-auto.log`.

> **Status: enabled on this machine** (2026-10-20). `/usr/local/sbin/plasma-patches-auto`,
> `/etc/systemd/system/plasma-patches-rebuild.service` (enabled under
> `multi-user.target`) and `auto/plasma-taskbar-patches.hook` installed over
> `/etc/pacman.d/hooks/plasma-taskbar-patches.hook`. `packaging/` still ships the
> reminder-only hook, so the repo's default stays the conservative one.
>
> Verified end to end, including what happens when it goes wrong:
>
> | Case | Result |
> |---|---|
> | already patched | logs `already patched, nothing to do`, exits 0 in milliseconds |
> | reverted binaries | rebuilt all three in ~5 min, reinstalled, restarted plasmashell, sent the notification |
> | patch no longer applies | aborts before installing anything, exits 1, logs `FAIL: … port needed`, working stock binaries stay in place |
>
> Enable on a fresh machine:
>
> ```sh
> cd ~/Documents/projects/plasma-taskbar-patches
> sudo install -m755 auto/plasma-patches-auto.sh      /usr/local/sbin/plasma-patches-auto
> sudo install -m644 auto/plasma-patches-rebuild.service /etc/systemd/system/
> sudo install -m644 auto/plasma-taskbar-patches.hook /etc/pacman.d/hooks/plasma-taskbar-patches.hook
> sudo systemctl daemon-reload && sudo systemctl enable plasma-patches-rebuild.service
> sudo /usr/local/sbin/plasma-patches-auto --check && echo patched
> ```
>
> To undo (back to the reminder-only hook):
>
> ```sh
> sudo systemctl disable --now plasma-patches-rebuild.service
> sudo rm /etc/systemd/system/plasma-patches-rebuild.service /usr/local/sbin/plasma-patches-auto
> sudo install -m644 packaging/plasma-taskbar-patches.hook /etc/pacman.d/hooks/plasma-taskbar-patches.hook
> sudo systemctl daemon-reload
> ```
>
> `rebuild.sh --build-only` is the seam: it stops before any `sudo`, so the
> unattended path never prompts for a password.

## Configuration

The Task Manager patch reads `~/.config/taskbar-compact.conf` at plasmashell
start — fonts, marquee, state-visual styles and colors, pulse timing, corner
radius, wheel-volume.

**Settings GUI:** run
[`taskbar-compact-launchers/gui/install-gui.sh`](taskbar-compact-launchers/gui/install-gui.sh)
(dependency: `pyside6`) and launch **Taskbar Compact Settings** from the app
menu. Every key is an explicit override with its default shown; *Apply* stops
plasmashell, writes the file, and restarts it — required because a live
plasmashell rewrites the file on exit.

Hand-editing instead: see
[`taskbar-compact-launchers/taskbar-compact.conf.example`](taskbar-compact-launchers/taskbar-compact.conf.example)
and the key table in that README. The tray and group-reorder patches configure
through the normal System Tray settings UI, applet config keys, and a
`PLASMA_INTRA_GROUP_MOVES` env var.

## Status / upstream

The systray "Very small" icon work was submitted upstream as KDE Invent MR
6833 (`sircanada/plasma-workspace`, branch `work/systray-very-small-icons`);
see `systray-2rows/MR-DESCRIPTION.md`. The rest is out-of-tree by nature
(opinionated behavior changes) or blocked on upstream design questions.

## License

GPL-2.0-or-later, matching the KDE Plasma sources these patches modify.
