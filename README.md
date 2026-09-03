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

Desk distance, not screen distance. The tracker reads motion straight off the
kernel's evdev devices, which is the raw stream *before* libinput's pointer
acceleration — so 400 counts on a 1000 DPI mouse is 1 cm of desk your hand
really crossed, whatever the cursor did on screen. That is the number worth
shrinking: the cursor crossing three ultrawides costs your shoulder nothing
extra if you flicked it there.

Touchpads count too. A mouse says how far it moved and a pad says where the
finger is, but they are two transducers for one act — a hand moving — so the
pad's positions are turned into the deltas a mouse would have sent and
everything downstream stays ignorant of the difference. Only the primary
finger contributes distance, because a two-finger scroll is still one hand;
a finger lifting and landing elsewhere contributes nothing, because your hand
did not travel that line. Two-finger scrolling is counted as scroll instead,
at 10 mm to the detent, so the column means the same thing on both.

Distance is summed per input report (usually 1000 a second), so a curved sweep
is measured along its curve rather than corner to corner.

*Active mousing* is wall-clock seconds in which the mouse moved at all. It is
what makes the **pace** row (metres per active hour) mean anything: it
reflects technique rather than how long you sat at the desk.

## Install

```bash
omarchy plugin add https://github.com/irhop/omarchy-mouse-odometer.git --enable --yes
```

That installs a widget and nothing else. **Enabling the plugin does not
install the tracker service** — the widget shows its icon and no number, and
clicking it opens a panel that tells you what setting it up would change and
waits for you to agree. Nothing touches systemd until you press the button.

If you would rather do it from a terminal:

```bash
cd ~/.config/omarchy/plugins/io.github.irhop.mouse-odometer
bin/omarchy-mouse-odometer bootstrap --dry-run   # what it would change
./install.sh                                     # do it, and put the widget on the bar
```

### What setting it up installs

The widget is a reader; the measuring is done by a small user service, so it
keeps counting when the shell restarts. Confirming the panel's setup card runs
`bin/omarchy-mouse-odometer bootstrap`, which:

- symlinks `systemd/omarchy-mouse-odometer.service` into `~/.config/systemd/user/`
  and starts it with `systemctl --user enable --now`
- symlinks the CLI into `~/.local/bin/` if that directory exists
- posts a desktop notification saying it has done so

The card lists those in full before you agree to them, and it lists them by
asking `bootstrap --dry-run` rather than from a description written here, so
what you are shown is what will run. The result — including a failure — is
reported back in the panel rather than swallowed.

Nothing runs as root, nothing is written outside those paths plus its own
state and config files, and no sudoers rule is touched. The CLI is launched
as an argv vector in an environment built from scratch, not as a shell string
inheriting the compositor's, and every external command it runs (`systemctl`,
`udevadm`, `ratbagctl`, the notifier) is resolved against a fixed
`/usr/local/bin:/usr/bin:/bin` rather than an ambient `PATH`. To undo all of
it, see [Uninstall](#uninstall).

On a laptop, note that a Windows Precision Touchpad publishes two evdev nodes
— the pad, and a relative "Mouse" collection kept for firmware older than the
standard. In precision mode, which is to say on every Linux machine, that
second node never emits an event. The pad speaks for the hardware and the
compat node is ignored, so `devices` lists one device, not two.

Reading the mouse needs membership in the `input` group and nothing more — no
root, no compositor hooks. If `id -nG` does not list `input`:

```bash
sudo usermod -aG input "$USER"    # then log out and back in
```

## DPI, and why it is not a prerequisite

Distance is counts divided by DPI, so the figure matters — but only for the
*absolute* numbers. DPI is a constant scale factor, so every comparison the
plugin makes (today against your baseline, this week against last, streaks,
the progress score) is completely unaffected by getting it wrong. That is why
the plugin starts counting immediately rather than holding your data hostage
until you find a ruler.

It works the figure out for itself where it can:

```bash
omarchy-mouse-odometer detect
```

| Source | What it is |
|---|---|
| **calibrated** | What you measured here. Beats everything else. |
| **hardware** | Read live from the mouse via `libratbag`, if installed. The only source that survives a DPI-button press. |
| **hwdb** | udev's mouse database, which ships a factory DPI for a few hundred known models. Free and automatic. |
| **the pad's own scale** | A touchpad reports its resolution in units per millimetre, because the hardware knows how big its glass is. Exact, automatic, and the reason a laptop never needs calibrating. |
| **assumed** | Nothing knows, so 1000 is used and the CLI says so. |

`omarchy-mouse-odometer devices` names the source it is using, and `status`
marks the distances as estimated whenever it is falling back to the assumption.
For a gaming mouse, installing `libratbag` is the best of both worlds: no
calibration, and it tracks hardware DPI changes.

## Calibrate

If nothing knows your mouse, measuring takes a ruler and a minute:

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

Passes that could not physically have happened are rejected rather than
averaged in: a reading below 200 or above 30000 DPI means the drag did not
cover the distance you said, most often because the second Enter arrived
before the hand moved. It tells you what it saw and retries.

Config lives in `~/.config/omarchy-mouse-odometer/config.json`, as either a
number or `{"x": 1600, "y": 900}`.

Changing the DPI only affects distance recorded from then on — but the history
can be brought onto the new scale, since raw counts are stored alongside
metres and distance is linear in DPI:

```bash
omarchy-mouse-odometer rescale --from 1000     # to your newly calibrated value
omarchy-mouse-odometer rescale --from 97 --to 1600
```

It stops the tracker while it rewrites, because the daemon holds the tally in
memory and would otherwise flush the old numbers back over the correction.

## Commands

```bash
omarchy-mouse-odometer status        # today / week / month / all time, with sparklines
omarchy-mouse-odometer status -v     # per-device breakdown
omarchy-mouse-odometer status --json # the raw state file
omarchy-mouse-odometer devices       # which pointers are being watched
omarchy-mouse-odometer bootstrap --dry-run   # what setting up would change
omarchy-mouse-odometer bootstrap             # install and start the service
omarchy-mouse-odometer uninstall --dry-run   # what removing it would take away
omarchy-mouse-odometer uninstall             # remove the service and the links
omarchy-mouse-odometer uninstall --purge     # ...and the recorded history
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
| `gamify` | `false` | Baseline, streak and personal best in the panel, streak badge in the bar |
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

## Progress tracking

Off by default; turn it on from the first-run card in the panel, or with
`omarchy bar set io.github.irhop.mouse-odometer gamify true`.

The score is **metres per desk hour** — metres divided by the hours in which
you used the machine at all. That denominator is the whole trick. Dividing by
*mousing* time instead measures how fast your hand sweeps, which is close to a
constant per person: reach for the keyboard instead of the mouse and you
remove both the metres and the seconds that produced them, so the ratio barely
moves. Dividing by desk hours means using the mouse less actually shows up,
and it can't be gamed by working a shorter day.

Once there is a fortnight of history the panel shows:

| | |
|---|---|
| **Your normal** | The median of your qualifying days. Median, not mean, so one afternoon of dragging windows around does not redefine normal. |
| **Streak under it** | Consecutive days below your own baseline. Days away from the machine are skipped, not counted as failures. |
| **Best day** | The lowest score you have posted. |
| **This week vs last** | The timescale a habit actually shows up on. |

A day needs at least two desk hours before it is scored — a ten-minute evening
check-in would otherwise post a wild number in either direction. The streak
count appears in the bar next to the distance once it reaches two days.

## Accuracy, honestly

**These are estimates, not measurements.** Treat them as a consistent yardstick
for comparing your own days, not as physical distance to three decimals:

- DPI calibration is a hand-drag against a ruler. The averaging helps, but a
  few percent of error survives it.
- Optical sensors vary with surface, lift height and hand speed. The same
  centimetre of mousepad does not always produce the same count.
- Mice with a hardware DPI button switch resolution invisibly to the kernel;
  everything recorded at the other setting is off by that ratio.
- Distance is summed per input report, so a flick fast enough to cover ground
  between two reports is measured as the straight line between them.
- Movement before login, or while the tracker is stopped, is not counted at all.

What it *is* good for: the shape of your day, whether this week is lighter than
last, and whether a change to your workflow actually moved the number.

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
omarchy-mouse-odometer uninstall --dry-run   # exactly what will be removed
omarchy-mouse-odometer uninstall             # service, unit link, CLI link
omarchy plugin remove io.github.irhop.mouse-odometer
```

`uninstall` stops and disables the service and removes the two symlinks — but
only if they still point back at this plugin; a same-named link to something
else belongs to whoever made it. Your history and DPI settings are kept, so
reinstalling picks up where you left off. To delete those too:

```bash
omarchy-mouse-odometer uninstall --purge
```

which additionally removes `~/.local/state/omarchy-mouse-odometer` and
`~/.config/omarchy-mouse-odometer`.

MIT licensed.
