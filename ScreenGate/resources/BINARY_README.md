# ScreenGate — compiled download

For Apple silicon and Intel Macs running macOS 12 or later, including Monterey 12.7.6. Xcode, Command Line Tools, and Rosetta are not required to install this download.

## Install

1. Extract the complete ZIP. Keep the `ScreenGate` folder and its contents together.
2. Open `Install.command`. If Finder blocks opening it, use its Open action, or run it with `bash` in Terminal.
3. Enter your Mac administrator password to install the background service. Choose a separate ScreenGate owner password of at least eight characters.
4. Open the shield menu, unlock the owner controls, and review the timetable and allowance.

The app is installed at `/Applications/ScreenGate.app`. The installer uses the compiled binaries; it does not download or run a compiler. The compiled download uses local ad-hoc code signatures and is **not Apple Developer ID signed or notarized**. macOS may require you to allow opening it using Finder's Open action or the Security & Privacy settings. Do not disable Gatekeeper globally.

The binaries target macOS 12.0. A successful build on the remote Mac does not establish live compatibility with Monterey 12.7.6; follow `MAC_TEST_CHECKLIST.md` before relying on enforcement.

## New in version 1.2.0

**Version 1.2.1:** hover over the menu-bar shield to see today's recorded screen time, refreshed about every two seconds. It includes school hours and offline use, just like the calendar. The tooltip works while owner controls are locked or closed; settings and history still require the owner password. Only the current console account can read this today-only summary. If recording has not begun or the service is unavailable, the tooltip says so.

- **Screen-time calendar:** select a date in the compact monthly calendar to see recorded awake, unlocked screen time, including school hours and offline use. Calendar totals keep recording when protection is paused, and stop when the owner uses Stop & Quit. Resetting the allowance counter preserves calendar history. All-day recording begins with this update after protection is resumed; older saved records are labeled after-school only. The first recording date shows when recording began.
- **Extra time for today:** add 15, 30, 60, or a custom number of minutes from owner controls. Extra time survives a restart for today, expires at local midnight, and leaves the regular daily allowance unchanged. The effective daily allowance cannot exceed 1,440 minutes. If the new allowance exceeds usage, ScreenGate restores connections it disabled; existing Pause/Stop states remain in effect.

To update, run this download's Install.command. Existing owner credentials, settings, and usage are preserved. The installer relaunches the current account's controls. Protection stays stopped after an upgrade; unlock the controls and click Resume protection. Keep the recovery scripts accessible offline.

## Controls

In-school time is unrestricted. After-school time accumulates while a screen is awake and the console session is unlocked. At the daily allowance, ScreenGate disables enabled network services, cutting local-network and internet access. Pause or Stop & Quit restores services it disabled. Stop & Quit requires the owner password. Closing or force-quitting the menu app leaves the root service running.

Defaults: 90 minutes daily; in-school Monday–Friday 09:00–15:30; after-school all day on all days. School windows take priority. Outside both modes the connection is unrestricted. Usage resets at local midnight. An awake, unlocked but idle screen counts; sleep and lock should not count. Pause and stopped states survive a restart.

Keep the Mac administrator password private and use a standard account for the person whose screen time is limited. A macOS administrator can override or remove this software.

## Recovery and removal

Keep `Recover.command` accessible offline. It requires Mac administrator access, restores journaled network services, and leaves protection stopped until the owner resumes. It does not reset the owner password.

`Uninstall.command` requires administrator access and confirmation. It restores connections before deleting the app and its settings. Reinstalling after removal lets you choose a new owner password.

If the protected state file is damaged and automatic restoration fails, unload the service with:

```sh
sudo launchctl bootout system /Library/LaunchDaemons/com.screengate.service.plist
```

Then use System Preferences → Network on Monterey, or System Settings → Network on newer systems, to reactivate the connections you want. Run the uninstaller only after restoring them.
