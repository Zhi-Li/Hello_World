#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
trap 'result=$?; if [[ $result -ne 0 ]]; then echo; echo "Installation stopped. See the error above."; fi; read -r -p "Press Return to close… " _done' EXIT
source resources/launchd-support.sh
if [[ -f Package.swift ]]; then
    bash scripts/build.sh
else
    # Binary downloads need only tools already included with macOS.
    if [[ "$(uname -s)" != "Darwin" ]] || \
       (( $(sw_vers -productVersion | cut -d. -f1) < 12 )); then
        echo "ScreenGate requires a Mac running macOS 12 or later." >&2
        exit 1
    fi
    if [[ ! -x dist/ScreenGate.app/Contents/MacOS/ScreenGate || ! -x dist/ScreenGateService ]]; then
        echo "The compiled app is missing. Extract the complete download before installing." >&2
        exit 1
    fi
    /usr/bin/codesign --verify --strict dist/ScreenGate.app
    /usr/bin/codesign --verify --strict dist/ScreenGateService
fi
echo
echo "Installing requires this Mac's administrator password."
sudo -v
state_dir="/Library/Application Support/ScreenGate"
service="$state_dir/ScreenGateService"
daemon="/Library/LaunchDaemons/com.screengate.service.plist"

# Stop a registered job by label, including after an interrupted installation.
if sudo launchctl print system/com.screengate.service >/dev/null 2>&1; then
    sudo launchctl bootout system/com.screengate.service
fi
# A blocked first initialization can leave a helper but no state to recover.
# Keep existing credentials and usage; never reinitialize an existing state.
if sudo test -f "$service" && sudo test -f "$state_dir/state.json"; then
    sudo "$service" --recover
fi
# Relaunch the current account's UI so an update opens the new controls.
pkill -x -u "$(id -u)" ScreenGate 2>/dev/null || true
sudo install -d -m 700 -o root -g wheel "$state_dir"
sudo install -m 700 -o root -g wheel dist/ScreenGateService "$service"
if ! sudo test -f "$state_dir/state.json"; then
    echo "Choose the ScreenGate owner password (at least 8 characters)."
    read -r -s -p "New owner password: " owner_password; echo
    read -r -s -p "Confirm password: " confirmation; echo
    if [[ "$owner_password" != "$confirmation" ]]; then echo "Passwords do not match." >&2; exit 1; fi
    printf '%s\n' "$owner_password" | sudo "$service" --initialize
    unset owner_password confirmation
fi
if [[ -e /Applications/ScreenGate.app ]]; then
    backup="$state_dir/ScreenGate-previous-$(date +%Y%m%d%H%M%S).app"
    sudo mv /Applications/ScreenGate.app "$backup"
fi
sudo ditto dist/ScreenGate.app /Applications/ScreenGate.app
sudo chown -R root:wheel /Applications/ScreenGate.app
sudo chmod -R go-w /Applications/ScreenGate.app
sudo install -m 644 -o root -g wheel resources/com.screengate.service.plist "$daemon"
sg_prepare_launchd_plist "$daemon"
sudo launchctl enable system/com.screengate.service
if ! sudo launchctl bootstrap system "$daemon"; then
    echo "macOS could not register the ScreenGate service. Your owner password and saved data have been kept."
    echo "For the specific reason, run this in Terminal:"
    echo "sudo log show --last 5m --style compact --predicate 'process == \"launchd\" AND eventMessage CONTAINS[c] \"screengate\"'"
    exit 1
fi

# A global login item starts the menu bar UI for every account; enforcement starts at boot.
agent="/Library/LaunchAgents/com.screengate.ui.plist"
sudo install -m 644 -o root -g wheel resources/com.screengate.ui.plist "$agent"
sg_prepare_launchd_plist "$agent"
echo
echo "ScreenGate installed. Use your owner password to review the schedule."
echo "On an upgrade, protection stays stopped until you click Resume protection."
open /Applications/ScreenGate.app
