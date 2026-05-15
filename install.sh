#!/usr/bin/env bash
set -euo pipefail

WIDGET_ID="wifi-signal-plus"

echo "Installing $WIDGET_ID …"
kpackagetool6 --install . --type Plasma/Applet 2>/dev/null \
  || kpackagetool6 --upgrade . --type Plasma/Applet

echo "Done. Add the widget from the panel's 'Add Widgets' menu."
echo "If it was already on your panel, run:  plasmashell --replace &"
