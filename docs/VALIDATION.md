# Validation record

Date: 2026-10-10 (Asia/Riyadh). Authoring host: Windows. No GitHub remote or Xcode/macOS build access has been supplied yet.

## Completed locally

- Parsed and checked the complete OpenStep Xcode project graph and shared scheme.
- Checked target/source membership, application dependency on the embedded extension, and app-extension copy destination.
- Parsed all Info.plist, entitlements and privacy manifest files; checked matching app group and Arabic localization.
- Generated and visually inspected an opaque RGB 1024×1024 app icon and included launch-screen artwork.
- Reviewed model schema defaults/CloudKit compatibility, pure calculations, migration path, recoverable persistence, PR idempotence, conflict rules, import validation and API contracts across modules.
- Wrote XCTest suites for formulas, invalid inputs, volumes/units, optimal plate composition, warmups, PR history, streak/averages, migrations, seed identity, conflict handling, JSON/CSV roundtrips and malformed imports.
- Wrote a main-flow XCUITest for plan creation → workout start → set completion → saved progress.
- XCTest source currently contains 22 unit tests and one UI test, all pending execution on macOS.
- Ran **7 portable tooling tests: 7 passed**. These validate entitlement expansion, project/plist structure, and rejection of missing extensions, mismatched groups and signed bundles. Packaging tests use synthetic headers only; they do not prove a real app executable works.

**Static checks and code review do not compile Swift and do not execute XCTest.**

## Pending macOS / CI

- Xcode build, zero-warning compiler gate, unit tests and UI test execution.
- Actual device archive, unsigned IPA packaging, arm64/extension verification and artifact upload.
- Real simulator screenshots at compact and large sizes and accessibility text sizes. Inspect numeric fields, Arabic calendar, axis labels, sheets and RTL swipe actions. Inspect both Western and Arabic-Indic digit modes, light and dark themes and Reduce Motion.
- Instruments allocation/leak and performance validation with at least two years of history. PR history calculation uses O(n log n); overall data/UI performance has not been measured.
- iOS 17 device/simulator compatibility as well as the CI iOS 18.5 simulator.

## Pending signed iPhone acceptance

1. Sign both executables with correct provisioning and install/launch.
2. Deny/allow/re-enable notifications and test rest foreground, background, lock screen, force quit and reopening. Inspect matching deadline and pause/resume elapsed times.
3. Test HealthKit unavailable/denied/granted, import body weight twice and retry completed-workout export; verify no duplicate Health workouts.
4. Use two devices with the same iCloud account: offline seed/edit/log, reconnect, inspect duplicate IDs, conflicting preferences/active plans, edited fields, images and status. Never claim a CloudKit event means every record reached another device.
5. Test home/lock widgets across midnight, week boundaries and program start dates; test Siri while app is closed, already active and locked; inspect Dynamic Island on a supported iPhone.
6. Enable app/photo lock, cancel authentication, background/foreground and inspect app switcher privacy cover. Test owner passcode fallback.
7. Export full JSON with photos and CSV with Arabic notes/newlines; restore into an empty installation and merge into populated data; ensure current records survive older backups.
8. Check VoiceOver, largest Dynamic Type, small iPhone and large iPhone, dark mode, keyboard one-handed logging and RTL charts/calendar navigation.

Until these gates pass, the App Store-level polish, no-crash/no-leak requirement, zero warnings and installability remain **unverified**, not promised as achieved.
