#!/usr/bin/env bash
# Sets up the tracker service and puts the widget on the bar.
# Installing through `omarchy plugin add` does not run this — the widget
# bootstraps itself on first load — but running it by hand is equivalent.
set -euo pipefail

PLUGIN_ID="odin.mouse-odometer"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$PLUGIN_DIR/bin/omarchy-mouse-odometer" bootstrap --force
systemctl --user --no-pager --lines=0 status omarchy-mouse-odometer.service || true

echo "==> Bar widget"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
omarchy plugin enable "$PLUGIN_ID" --section right || true

echo
echo "Done. Calibrate your mouse so the distances are real:"
echo "    omarchy-mouse-odometer calibrate"
echo "Until then it assumes 1000 DPI."
