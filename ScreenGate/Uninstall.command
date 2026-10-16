#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
trap 'read -r -p "Press Return to close… " _done' EXIT
echo "This removes ScreenGate, its owner password, schedule, and usage records."
read -r -p "Type REMOVE to continue: " confirmation
[[ "$confirmation" == "REMOVE" ]] || exit 0
sudo -v
if sudo launchctl print system/com.screengate.service >/dev/null 2>&1; then
    sudo launchctl bootout system/com.screengate.service
fi
if ! sudo "/Library/Application Support/ScreenGate/ScreenGateService" --recover; then
    echo "Automatic restoration failed. Connections may still be disabled."
    echo "Restore wanted connections in System Preferences/Settings > Network before removing the recovery records."
    read -r -p "Type RESTORED only after restoring connections, or Return to keep all files: " restoration
    [[ "$restoration" == "RESTORED" ]] || exit 1
fi
current_uid=$(id -u)
sudo launchctl bootout "gui/$current_uid/com.screengate.ui" 2>/dev/null || true
killall ScreenGate 2>/dev/null || true
sudo rm -f /Library/LaunchAgents/com.screengate.ui.plist /Library/LaunchDaemons/com.screengate.service.plist
sudo rm -rf /Applications/ScreenGate.app "/Library/Application Support/ScreenGate"
echo "ScreenGate removed; connections restored."
