#!/bin/bash
# launchd on macOS 27 rejects quarantined property lists, independently of
# approval for the executable. Only prepare ScreenGate's configuration files;
# executable approval remains a separate Gatekeeper decision.
sg_prepare_launchd_plist() {
    local plist="$1"
    sudo /usr/bin/plutil -lint "$plist" || return $?
    if sudo /usr/bin/xattr -p com.apple.quarantine "$plist" >/dev/null 2>&1; then
        sudo /usr/bin/xattr -d com.apple.quarantine "$plist" || return $?
    fi
    return 0
}
