#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
trap 'read -r -p "Press Return to close… " _done' EXIT
echo "Administrator recovery: stops ScreenGate and restores connections it disabled."
sudo -v
sudo launchctl bootout system /Library/LaunchDaemons/com.screengate.service.plist 2>/dev/null || true
sudo "/Library/Application Support/ScreenGate/ScreenGateService" --recover
sudo launchctl bootstrap system /Library/LaunchDaemons/com.screengate.service.plist
echo "Open ScreenGate and use Resume protection when ready."
