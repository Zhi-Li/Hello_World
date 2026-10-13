# ScreenGate

A native menu bar app for **Apple silicon and Intel Macs running macOS 12 or later, including Monterey 12.7.6**. It has password-protected owner controls and a separate privileged background service that manages a daily after-school screen-time allowance.

**This download is a source project with a Mac build/install script, not a precompiled or notarized app.** The first build must run on a Mac. No third-party packages, cloud accounts, subscriptions, or network access are needed after Apple's build tools are installed.

## Install

1. Extract the ZIP on your Mac.
2. Open `Install.command` from the extracted `ScreenGate` folder. If Finder blocks opening it, use Finder's **Open** action or open Terminal, type `bash `, drag `Install.command` into Terminal, then press Return.
3. If Apple's Command Line Tools are missing, the script requests their installation. Finish installing them, then run `Install.command` again. Swift **5.7 or later** is required. On macOS **12.7.6**, use **Xcode 14.2** or compatible Command Line Tools, available from [Apple Developer Downloads](https://developer.apple.com/download/all/). Xcode 14.2 includes Swift 5.7 and runs on Monterey 12.5 or later. If you use the full Xcode app, select it with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` and complete its first-launch setup before building.
4. The script runs the Swift tests, compiles **arm64 and x86_64**, combines each pair into a universal binary, and verifies both architectures and local signatures. A failing test or build stops before any installation changes.
5. Enter your **Mac administrator password** to install the protected service. Then choose a separate **ScreenGate owner password**, at least 8 characters, and confirm it.
6. Open the shield in the menu bar, choose **Open owner controls**, and enter your owner password. Review the schedule and daily limit.

The built application is installed as `/Applications/ScreenGate.app`. Build tools are only needed to build or update it. Both binaries support both chip families; an Apple silicon Mac does not need Rosetta to run the app.

To build without installing, run `Build.command`. Outputs appear in `dist/`.

## Compile remotely without Xcode on your Mac

The repository includes a manually triggered GitHub Actions workflow in `.github/workflows/build-macos.yml`. It runs native tests and builds both architectures on a hosted Mac, then uploads `ScreenGate-macOS-universal.zip`. Place the contents of this `ScreenGate` folder at the repository root, including `.github`, and run **Build ready-to-install Mac app** from the repository's Actions page. Check the account's Actions allowance before running in a private repository.

The compiled ZIP contains the app, service, and installer. Its `Install.command` skips compilation, so the destination Mac needs no Xcode or Command Line Tools. `bash scripts/package-binary.sh` creates the same ZIP after a successful local build. The release has ad-hoc signatures; Apple Developer ID signing and notarization require distributor credentials. No compiled release has been produced in the Linux authoring environment.

Version **1.1.0** replaces the newer SwiftUI menu-bar/window APIs with AppKit `NSStatusItem`, `NSWindow`, and `NSHostingView`. It targets macOS 12.0 for **both** binaries and uses the SwiftPM 5.7-compatible build-path option when needed. Password controls and background enforcement follow the same behavior on Monterey and newer systems. Compatibility is a build target; actual execution on 12.7.6 still needs the first-run checks below.

## What it does

| Control or state | Behavior |
| --- | --- |
| In-school | Internet is unrestricted; this time does not consume the daily allowance. |
| After-school | Accumulates screen-awake, unlocked time across all logged-in console accounts on this Mac. At the allowance, network services are disabled. |
| Pause | Stops counting and restores connections disabled by ScreenGate. Pause persists through a restart until the owner resumes. |
| Resume | Restarts counting/enforcement. If today's allowance is already used, the connection is blocked again during after-school time. |
| Stop & Quit | Requires a fresh owner password, restores connections, saves the stopped state, and exits the app and service. Protection stays stopped when reopened or rebooted until the owner resumes. |
| Close the owner window | Locks the controls. Background enforcement continues. |
| Reset today's usage | Sets the allowance used today to zero and reevaluates the connection. Owner access required. |
| Change password | Requires the current owner password. Other unlocked sessions are invalidated. |

The menu bar app starts at login, and the root service starts at boot. The service also supports launchd socket activation, so reopening the app can reach the service after an owner-approved exit. An unexpected service crash is configured to restart through launchd. Force-quitting the menu bar app does not stop the root enforcement service.

## Scheduling and counting

Defaults are **90 minutes per calendar day**, in-school **Monday–Friday, 09:00–15:30**, and after-school **all days, all day**. Because in-school windows take priority, the default after-school mode applies everywhere outside weekday school hours, including weekends and evenings.

You can add multiple windows for either mode, select weekdays, set start/end times, and select All day. **In-school always takes priority when windows overlap. Outside both sets of windows, the Mac is unrestricted.** Keep an all-day after-school window if you want every non-school minute covered.

An overnight window such as Friday 22:00–02:00 continues through Saturday 02:00. Its weekday refers to the starting day. Start is inclusive; end is exclusive. Equal start/end times require the All day option.

The allowance resets at **local midnight**, following the Mac's current timezone. It is shared across all after-school windows that day and all console accounts. Sleep, a locked screen, and the login screen do not intentionally consume time. Watching a video, reading without typing, and an idle but awake and unlocked screen do consume time. This is screen-on time, not Apple's per-app Screen Time database.

The timer samples once per second; short samples are split at timetable and day boundaries. Sleep gaps are discarded. Daily usage is saved atomically as it is updated, and a restart does not deliberately reset it. Timing can lose a small amount around a crash, a lock transition, or a stalled system. The screen-state detection, including lock behavior, must be checked on the target macOS version as described in `MAC_TEST_CHECKLIST.md`.

## Network behavior

The service disables macOS network services using SystemConfiguration, including enabled Wi-Fi and Ethernet services. This cuts local-network access as well as internet access; localhost communication with owner controls remains available. It does not overwrite DNS, remove saved Wi-Fi passwords, switch off the Wi-Fi radio, or replace firewall rules.

Before changing any enabled service, ScreenGate writes its stable service UUID to a protected restoration journal. On Pause, in-school time, reset, or Stop & Quit, it reenables only the services in that journal. Services that were already disabled stay disabled. New/re-enabled services are checked every five seconds while blocked. Network changes and restoration can take a few seconds; the owner window displays errors and the service retries failures.

Ordinary Wi-Fi and Ethernet setups are the intended deployment. Verify USB tethering, VPN software, custom network extensions, external monitors, and fast user switching on the target Mac before relying on it.

## Owner protection and recovery

The owner password is stored as a randomly salted PBKDF2-HMAC-SHA256 record using 600,000 iterations, in a root-owned file. Passwords are not stored as plaintext or placed in command-line arguments. Authenticated session tokens are bound to a local user ID and expire after 15 minutes. The controls automatically lock after five minutes without interaction, when the app loses focus, or when the owner window closes. Failed passwords are rate-limited.

**A macOS administrator/root user can remove, stop, or modify this app.** Give a child a standard macOS account and keep the administrator password private if this is used for parental controls. No ordinary user-space app can guarantee protection against an administrator, Recovery Mode, reinstalling macOS, or external boot access. Closing or force-quitting the UI is not equivalent to stopping the protected service.

Keep `Recover.command` somewhere available offline. If restoration fails or you cannot access the owner controls:

1. Run `Recover.command` and authenticate as a Mac administrator.
2. It unloads the daemon, sets protection to stopped, restores the journaled services, and reloads the stopped service so owner controls remain available.
3. Open ScreenGate and Resume when ready. Recovery does **not** change the owner password. If that password is lost, the administrator can uninstall and reinstall; that deletes the old schedule and usage.

If the state file is damaged and recovery cannot read it, stop the service first:

```sh
sudo launchctl bootout system /Library/LaunchDaemons/com.screengate.service.plist
networksetup -listallnetworkservices
```

Then use **System Preferences → Network** on Monterey, or **System Settings → Network** on newer macOS, to make the intended services active. Alternatively use `sudo networksetup -setnetworkserviceenabled "Wi-Fi" on` for a service actually named Wi-Fi. Enable only the services you want. Run `Uninstall.command` after restoring the connection; see its state-damage handling prompt.

## Updating or removing

Run `Install.command` again to update. The previous service restores connections before replacement. The owner password, schedule, and usage are preserved. Protection stays **stopped** after an upgrade until the owner resumes. A copy of the previous app is retained in the protected support directory.

Run `Uninstall.command` and enter `REMOVE` to remove the application, launch jobs, password, schedule, and usage. It requires Mac administrator access and restores connections before deleting data. If automatic restoration fails, it keeps the recovery records unless you explicitly type `RESTORED` after manually restoring the wanted connections in System Preferences/Settings. For damaged state, use the recovery procedure above first.

## Project and validation

Open `Package.swift` in Xcode or use the included shell scripts. The project uses SwiftUI/AppKit for the UI, a Swift root service, SystemConfiguration for network management, and a small C policy engine with a macOS API bridge. There are no Swift package dependencies.

`VALIDATION.md` records completed checks. The portable C policy tests passed on Linux with address/undefined-behavior sanitizers. Native Swift unit tests and compilation for both architectures passed on GitHub's macOS 15 Intel runner. **Live networking, owner-window interaction, and execution on Monterey 12.7.6 or a physical Apple silicon Mac still require verification.** The source `Install.command` runs native tests and builds before installing; the binary release installer uses the precompiled outputs. Follow `MAC_TEST_CHECKLIST.md` on the target Mac.

Technical references:

- [Apple: Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
- [Apple: SCNetworkServiceSetEnabled](https://developer.apple.com/documentation/systemconfiguration/scnetworkservicesetenabled(_:_:))
- [Apple: CGSessionCopyCurrentDictionary](https://developer.apple.com/documentation/coregraphics/cgsessioncopycurrentdictionary())
- [Apple: CGDisplayIsAsleep](https://developer.apple.com/documentation/coregraphics/cgdisplayisasleep(_:))
- [Apple: Xcode 14.2 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-14_2-release-notes)
