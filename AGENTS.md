# Working on this plugin

## Shape

| File | Role |
|---|---|
| `bin/omarchy-mouse-odometer` | Python 3 daemon + CLI. No third-party imports — keep it that way, it has to run before anything is installed. |
| `Format.js` | Every number the user sees is derived here, so the bar and the panel can never disagree. |
| `Sparkline.qml` | The graph, used at 12px in the bar and at 44px in the panel. |
| `BarWidget.qml` | Bar entry point. Owns the `FileView`, the parsed state, and every setting. |
| `Panel.qml` | The popup. Reads everything off `hostWidget`; it never parses state itself. |

## Rules that matter

- **Enabling the plugin installs nothing.** Loading a widget from a marketplace
  must not link a unit, write a symlink or start a service. `bootstrap` is
  reached from exactly two places, both of them a deliberate act: the panel's
  setup card, after it has shown `bootstrap --dry-run` and been told to go
  ahead, and `install.sh`. Nothing may call it on load, on first paint, or on
  a failed state read. If a new entry point needs it, it needs a consent
  screen first.
- **The consent screen is generated, not written.** It lists what
  `bootstrap_plan()` reports for this machine. Describing the same steps in
  prose somewhere else is how the two drift apart.
- **No shell strings, no ambient environment.** Every external command goes
  through `run_tool()` (Python) or a `Process` with `clearEnvironment` (QML):
  argv vectors, executables resolved against `SAFE_PATH`, and an environment
  built from `ENV_KEEP` rather than inherited. A service installer reachable
  from a bar widget must not pick up whatever `PATH` the compositor started
  with.
- **Anything installed must be removable.** `uninstall` reverses `bootstrap`
  and only unlinks symlinks that still point back here. History and DPI
  settings survive without `--purge`.
- **The daemon is the only thing that touches `/dev/input`.** The QML side is a
  reader of one JSON file. Keep it that way: anything else would put evdev
  parsing inside the compositor's shell process.
- **State is metres, not counts.** Counts are kept for the record, but DPI can
  change, so distance is converted at write time and never recomputed.
- **Divide each axis before the hypotenuse.** `hypot(dx/dpiX, dy/dpiY)`, never
  `hypot(dx, dy)/dpi` — on a mouse with asymmetric resolution the second form
  is wrong in proportion to how far the stroke leans towards the odd axis.
  A DPI setting is a scalar *or* `{"x": n, "y": n}`; `as_axes()` normalises it.
- **Buckets are three-way.** Day, all-time, and per-device. Route new counters
  through `Tracker.tally()` — an earlier version incremented only the day
  bucket and the all-time clicks silently stayed at zero.
- **Hourly detail is sparse and pruned.** Only hours with movement are stored,
  and only for `HOURLY_KEEP_DAYS`; otherwise the state file grows without
  bound for data nobody reads.
- **The score is metres per *desk* hour, never per mousing hour.** Dividing by
  time-the-mouse-was-moving measures sweep speed, which is near-constant per
  person and barely responds to using the mouse less — the exact thing the
  score exists to reward. Desk hours are hours with any movement in them,
  counted from the sparse hourly buckets into `desk_hours` so the number
  survives hourly pruning.
- **Baselines are medians and days are qualified.** A day under two desk hours
  is not scored, and one wild afternoon must not redefine normal. Days away
  from the machine skip the streak rather than breaking it.
- Settings live in the widget's `shell.json` layout entry, written through
  `persist()` so a click survives a restart. Nothing else may write there.

- **Never rewrite the state file while the daemon runs.** It holds the whole
  tally in memory and flushes every 15s, so an edit underneath it is silently
  reinstated. `rewriting_state()` stops and restarts around the write; use it.
- **DPI only scales absolute distance.** Every comparison in the UI is
  scale-invariant, so a wrong DPI is never a reason to block or discard data —
  and `rescale` can move a history onto a corrected figure exactly, because
  raw counts are kept next to metres.

## Testing

There is no uinput access under a normal user, so the daemon's event path is
tested by feeding packed `input_event` structs through a pipe — see the commit
history for the harness. The struct is `struct.Struct("llHHi")`, 24 bytes on
64-bit; verify that before blaming anything else.

Check QML changes with:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/io.github.irhop.mouse-odometer
omarchy-shell shell rescanPlugins
qs -p /usr/share/omarchy/shell log | grep -i odometer
```
