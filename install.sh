#!/usr/bin/env bash
# Sets up the tracker service and puts the widget on the bar.
# Running this is one of the two ways to consent to the service being
# installed; the other is the panel's setup card. Installing through
# `omarchy plugin add` runs neither, and installs nothing: enabling a plugin
# gets you a widget that reads a file, and that is all.
# See what it would do first with:
#     bin/omarchy-mouse-odometer bootstrap --dry-run
set -euo pipefail

PLUGIN_ID="io.github.irhop.mouse-odometer"
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
