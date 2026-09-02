# Mouse Odometer

A live graph of how far your mouse has actually travelled, in the Omarchy bar.

```
󰍽 ▁▂▃▅▇▃▁▁▂▅▃▁▂▁▁▂ 412m ↓12%
```

Icon, sparkline of the last 16 hours, the distance so far today, and how that
compares to your last seven days. The arrow is the point: it is the difference
between a number and a habit.

| Click | Does |
|---|---|
| Left | Opens the history panel |
| Right | Cycles the number: today → this week → all time |
| Middle | Cycles the graph: hours → days → off |

The panel behind it holds today hour by hour, the last 14 days with the
average drawn as the line you are trying to stay under, and the totals —
clicks, scroll ticks, active mousing time, and your pace in metres per active
hour. Hover any column for its own numbers; `u` switches units, `r` refetches.

## What it measures

Desk distance, not screen distance. The tracker reads relative motion straight
off the kernel's evdev devices, which is the raw stream *before* libinput's
pointer acceleration — so 400 counts on a 1000 DPI mouse is 1 cm of desk your
hand really crossed, whatever the cursor did on screen. That is the number
worth shrinking: the cursor crossing three ultrawides costs your shoulder
nothing extra if you flicked it there.

Distance is summed per input report (usually 1000 a second), so a curved sweep
is measured along its curve rather than corner to corner.

*Active mousing* is wall-clock seconds in which the mouse moved at all. It is
what makes the **pace** row (metres per active hour) mean anything: it
reflects technique rather than how long you sat at the desk.

## Install

```bash
omarchy plugin add https://github.com/irhop/omarchy-mouse-odometer.git --enable --yes
```

The widget bootstraps its own tracker the first time it loads — installing the
plugin is the only step. If you cloned it by hand instead:

```bash
~/.config/omarchy/plugins/io.github.irhop.mouse-odometer/install.sh
```

### What it installs

The widget is a reader; the measuring is done by a small user service, so it
keeps counting when the shell restarts. On first load the widget runs
`bin/omarchy-mouse-odometer bootstrap`, which:

- symlinks `systemd/omarchy-mouse-odometer.service` into `~/.config/systemd/user/`
  and starts it with `systemctl --user enable --now`
- symlinks the CLI into `~/.local/bin/` if that directory exists
- posts a desktop notification saying it has done so

Nothing runs as root, nothing is written outside those paths plus its own
state and config files, and no sudoers rule is touched. Set `autostart` to
`false` on the widget if you would rather start the service yourself — the
panel has a **Start tracker** button, and `install.sh` does the same job. To
undo all of it, see [Uninstall](#uninstall).

Reading the mouse needs membership in the `input` group and nothing more — no
root, no compositor hooks. If `id -nG` does not list `input`:

```bash
sudo usermod -aG input "$USER"    # then log out and back in
```

## Calibrate

Distances are only as good as the DPI they are divided by, and the default
guess is 1000. Measuring yours takes a ruler and a minute:

```bash
omarchy-mouse-odometer calibrate
```

It runs **three passes on each axis** and averages them, because one
hand-drag carries real error — parallax at the start and stop marks, a lift,
an uneven pace. Each pass reports its own reading so a bad one is obvious,
and the spread is printed at the end; more than 5% disagreement means the
number is not yet trustworthy and a longer drag will steady it.

```bash
omarchy-mouse-odometer calibrate --cm 30     # longer drag, less end-point error
omarchy-mouse-odometer calibrate --repeat 5  # more passes
omarchy-mouse-odometer calibrate --axis x    # one axis only
```

**Why both axes.** Most mice have a single square-resolution sensor, so
horizontal and vertical come out the same and the reading is stored as one
number. Plenty of gaming mice expose independent X and Y resolution, though,
and there a single number would be silently wrong for vertical movement in
proportion to how far a stroke leans that way. So it measures both, and
stores them separately only when they differ by more than 3% — otherwise the
difference is measurement noise and averaging is the honest answer.

Each pass measures **net displacement**, not path length: a ruler records
where the mouse ended up, so a wobble that goes out and comes back cancels,
exactly as it does on the desk.

Note that your *screens* play no part in this. DPI is a property of the mouse
sensor — counts per inch of desk travelled — and the daemon reads those counts
before the compositor turns them into cursor movement. Resolution, scaling and
monitor count change nothing.

If you already know the figure, set it directly:

```bash
omarchy-mouse-odometer set-dpi 1600
omarchy-mouse-odometer set-dpi 800 --device "Logitech"    # per-mouse
omarchy-mouse-odometer set-dpi 900 --axis y               # one axis
omarchy-mouse-odometer restart
```

Config lives in `~/.config/omarchy-mouse-odometer/config.json`, as either a
number or `{"x": 1600, "y": 900}`. Changing the DPI only affects distance
recorded from then on.

## Commands

```bash
omarchy-mouse-odometer status        # today / week / month / all time, with sparklines
omarchy-mouse-odometer status -v     # per-device breakdown
omarchy-mouse-odometer status --json # the raw state file
omarchy-mouse-odometer devices       # which pointers are being watched
omarchy-mouse-odometer bootstrap     # install and start the service
omarchy-mouse-odometer reset --today
omarchy-mouse-odometer reset --all
```

```
14 days     ▁▁▁▂▅▃▂▇█▅▃▂▁▄  (now 412 m)
Today       ▁▁▁▁▁▁▂▅▇█▅▃▂▁▁▁▁▁▁▁▁▁▁▁  hour by hour, 00-23
```

## Settings

Set them on this widget's layout entry in `~/.config/omarchy/shell.json`, or
with `omarchy bar set`:

| Key | Default | What it does |
|---|---|---|
| `units` | `metric` | `metric` (m/km) or `imperial` (ft/mi) |
| `show` | `today` | The number: `today`, `week` or `total` |
| `graph` | `hours` | `hours`, `days`, or `off` |
| `graphPoints` | `16` | How many hours or days the sparkline covers (4–48) |
| `graphBarWidth` | `2` | Column width in pixels (1–6) |
| `showDelta` | `true` | The ↓12% trend arrow |
| `showNumber` | `true` | Turn off for a graph-only widget |
| `goalMeters` | `0` | Daily budget in metres; the widget turns urgent above it |
| `autostart` | `true` | Install and start the tracker service on first load |
| `icon` | `󰍽` | Glyph in front of the graph |

```json
{ "id": "io.github.irhop.mouse-odometer", "graph": "hours", "graphPoints": 24, "goalMeters": 300 }
```

A goal is the part that actually changes behaviour: pick a number a little
under your current daily average (the panel shows it), and the bar tells you
when you have spent it.

On a vertical bar the widget collapses to its icon; the graph and the numbers
move into the tooltip and the panel.

## Where things live

| Path | What |
|---|---|
| `bin/omarchy-mouse-odometer` | tracker daemon + CLI (Python 3, no dependencies) |
| `systemd/omarchy-mouse-odometer.service` | the user service |
| `~/.local/state/omarchy-mouse-odometer/state.json` | the tally, rewritten every 15s |
| `~/.config/omarchy-mouse-odometer/config.json` | DPI settings |

The daemon holds one file descriptor per mouse and wakes only when the mouse
moves. Daily history is kept for 400 days; the hour-by-hour detail behind the
graph is kept for 7 and then rolls off, so the state file stays small.

## Dependencies

None beyond a stock Omarchy system:

| Needs | Why |
|---|---|
| Python 3 (standard library only) | The tracker daemon and CLI. No pip packages, no build step. |
| systemd user session | Keeps the tracker running across shell restarts. |
| Membership of the `input` group | Reading `/dev/input/event*`. Standard on Omarchy. |

It makes no network requests of any kind, bundles no binaries, and builds
nothing at install time.

## Limitations

- **Touchpads are not counted.** They report absolute positions, not relative
  counts, so there is no DPI to divide by. External mice, trackballs and
  trackpoints all work.
- **DPI switching on the fly** (the button some mice have) is invisible to the
  kernel, so distance recorded at another DPI setting is off by that ratio.
- The daemon starts with your user session, so movement before login or while
  it is stopped is not counted.

## Uninstall

```bash
systemctl --user disable --now omarchy-mouse-odometer.service
rm ~/.config/systemd/user/omarchy-mouse-odometer.service ~/.local/bin/omarchy-mouse-odometer
omarchy plugin remove io.github.irhop.mouse-odometer
rm -rf ~/.local/state/omarchy-mouse-odometer ~/.config/omarchy-mouse-odometer
```

MIT licensed.
