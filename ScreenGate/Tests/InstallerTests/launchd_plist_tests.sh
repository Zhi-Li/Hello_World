#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ "$(uname -s)" == Darwin ]] || { echo "These checks require macOS xattr and plutil." >&2; exit 1; }
source resources/launchd-support.sh
# Work only on user-owned temporary files; never register a real service or
# request privileges on the build runner.
sudo() { "$@"; }
temporary=$(mktemp -d "${TMPDIR:-/tmp}/screengate-plist-test.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
for name in com.screengate.service com.screengate.ui; do
    source_plist="resources/$name.plist"
    installed="$temporary/$name.plist"
    cp "$source_plist" "$installed"
    /usr/bin/xattr -w com.apple.quarantine '0083;00000000;ScreenGateInstallerTest;' "$installed"
    /usr/bin/xattr -w com.screengate.installer-test preserve "$installed"
    sg_prepare_launchd_plist "$installed"
    if /usr/bin/xattr -p com.apple.quarantine "$installed" >/dev/null 2>&1; then
        echo "FAIL: quarantine remained on $name" >&2; exit 1
    fi
    [[ "$(/usr/bin/xattr -p com.screengate.installer-test "$installed")" == preserve ]]
    cmp -s "$source_plist" "$installed"
    # Repeating installation must also succeed when no quarantine flag remains.
    sg_prepare_launchd_plist "$installed"
done
invalid="$temporary/invalid.plist"
printf '%s\n' 'not a property list' > "$invalid"
/usr/bin/xattr -w com.apple.quarantine '0083;00000000;ScreenGateInstallerTest;' "$invalid"
if sg_prepare_launchd_plist "$invalid" >/dev/null 2>&1; then
    echo "FAIL: invalid configuration was accepted" >&2; exit 1
fi
/usr/bin/xattr -p com.apple.quarantine "$invalid" >/dev/null
echo "PASS: both launchd plists lose quarantine, preserve contents/other attributes, support retries, and reject invalid data."
