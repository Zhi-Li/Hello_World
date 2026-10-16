#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source resources/launchd-support.sh
trap 'read -r -p "Press Return to close… " _done' EXIT
echo "Administrator recovery: stops ScreenGate and restores connections it disabled."
sudo -v
if sudo launchctl print system/com.screengate.service >/dev/null 2>&1; then
    sudo launchctl bootout system/com.screengate.service
fi
sudo "/Library/Application Support/ScreenGate/ScreenGateService" --recover
sg_prepare_launchd_plist /Library/LaunchDaemons/com.screengate.service.plist
sudo launchctl enable system/com.screengate.service
sudo launchctl bootstrap system /Library/LaunchDaemons/com.screengate.service.plist
echo "Open ScreenGate and use Resume protection when ready."
