# Validation record

Authoring environment: Linux x86_64, 11 October 2026. Apple SDKs, Swift, Xcode, and a live Mac were unavailable.

Remote native checks, 13 October 2026: GitHub's macOS 15 Intel runner, using Xcode 16.4, compiled the application and service for arm64 and x86_64 and passed all eight Swift unit tests. An initial packaging failure revealed the incorrect argument order for `lipo -verify_arch`; the scripts now put the input file first. Nullable service identifiers and the public status initializer were corrected after the first native compile. Shared protocol values are Sendable. The screen-state bridge now accepts the IORegistry `CGSSessionScreenIsLocked` key as well as the legacy prefixed spelling. These checks do not test live enforcement on a person's Mac or establish execution on Monterey 12.7.6.

Completed:

- Version 1.3.0 records daily in-school/after-school categories independently of allowance charging, with an explicit bucket for schedule gaps. Automated checks cover boundaries, midnight, DST, offline/paused measurements, reset preservation, schedule-edit stability, total-only history migration, bonus preservation, invalid split rejection, wire round trips, and tooltip splits. Existing total-only history remains unsplit instead of being guessed from today's settings.

- Version 1.2.1 adds a current-console, read-only today summary for the menu-bar tooltip, with tests for duration formatting, midnight rollover, missing/invalid totals, and a wire response without owner status/history/session data. The owner-window polling path still requires authentication; the locked path fetches only the minimal summary.

- Version 1.2.0 adds automated accounting coverage for school/offline totals, resets preserving history, paused/stopped behavior, sleep/clock gaps, midnight and DST splits, extension persistence and bounds, legacy history labeling, month filtering, and wire messages. The hosted Mac build runs these tests along with the existing tests before packaging.

- Built and ran the **actual C policy engine**, with `-Wall -Wextra -Werror -pedantic` and address/undefined-behavior sanitizers. Passed all 10,080 minutes of the default weekly schedule plus overnight/week-wrap boundaries, invalid windows, unrestricted gaps, inactive screens, pauses, stopped protection, sleep gaps, invalid elapsed values, exact-limit blocking, and allowance accumulation across windows.
- Validated shell syntax for build, install, recovery, uninstall, and portable test scripts.
- Parsed all launchd/application property lists and checked the socket mode, service executable path, and successful-exit behavior.
- Reviewed local authentication, token binding, journal-before-disable ordering, restoration of previously enabled services, default schedule precedence, and arm64/x86_64 packaging paths.
- For version 1.1.0, replaced macOS 13-only menu/window APIs with AppKit lifecycle management, moved weekday font styling onto Text for Monterey compatibility, and checked that the package, installer, and app metadata all target macOS 12.0 with a Swift 5.7 manifest.
- Exercised the build script with mocked Mac tools: Swift 5.7.2 selects `--build-path`, Swift 5.9.2/6.2 select `--scratch-path`, and each successful path requests arm64 and x86_64 builds with deployment target 12.0. Swift 5.6.3, an unparseable Swift version, and macOS 11 are rejected before builds. These checks validate script branching and arguments, not native compilation or executable compatibility.
- Added a hosted-Mac workflow and a binary-release packager. The binary installer checks signatures and skips compilation. The workflow runs on the separate `screengate-build` branch; its native tests and both architecture compilations passed before the packaging argument-order fix.

Not completed here:

- Live UI interaction and running the privileged service against the runner's network settings (the remote build does not install the service or change the runner's network).
- Real screen lock, sleep, external-display, or user-switching behavior.
- Actual service disabling/restoration, VPN/tethering behavior, and launchd lifecycle.
- Execution on macOS 12.7.6 or either macOS architecture, notarization, or a signed distributor installer.

The Mac build script runs native tests, compiles both architectures, and verifies the generated universal binaries before installation. Live behavior still needs the checks in MAC_TEST_CHECKLIST.md.

Reproduce the portable checks with:

```sh
ASAN_OPTIONS=detect_leaks=0 bash scripts/test-policy.sh
```

Leak detection was disabled because the container's process supervisor prevents LeakSanitizer from inspecting `/proc`; address and undefined-behavior checks remained enabled.
