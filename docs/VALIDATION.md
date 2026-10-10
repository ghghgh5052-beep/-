# Validation record

Date: 2026-10-10 (Asia/Riyadh). Authoring host: Windows. Source is connected to `https://github.com/ghghgh5052-beep/-`; native builds run on GitHub's macOS 15 runner with Xcode 16.4.

## Completed locally

- Parsed and checked the complete OpenStep Xcode project graph and shared scheme.
- Checked target/source membership, application dependency on the embedded extension, and app-extension copy destination.
- Parsed all Info.plist, entitlements and privacy manifest files; checked matching app group and Arabic localization.
- Generated and visually inspected an opaque RGB 1024×1024 app icon and included launch-screen artwork.
- Reviewed model schema defaults/CloudKit compatibility, pure calculations, migration path, recoverable persistence, PR idempotence, conflict rules, import validation and API contracts across modules.
- Wrote XCTest suites for formulas, invalid inputs, volumes/units, optimal plate composition, warmups, PR history, streak/averages, migrations, seed identity, conflict handling, JSON/CSV roundtrips and malformed imports.
- Wrote a main-flow XCUITest for plan creation → workout start → set completion → saved progress.
- XCTest source contains 22 unit tests and one UI test. All 23 passed on iPhone SE (3rd generation), iOS 18.5 in the first successful native build.
- Ran **10 portable tooling tests: 10 passed**. These validate entitlement expansion from separate native target settings, rejection of incomplete signing manifests, project/plist structure, and rejection of missing extensions, missing App Intent metadata, mismatched groups and signed bundles. Packaging tests use synthetic headers only; they do not prove a real app executable works.

**Static checks and code review do not compile Swift and do not execute XCTest.**

## Completed native build

- [First passing Actions run](https://github.com/ghghgh5052-beep/-/actions/runs/38017392175), source commit `e6a58c5775052c396ccc62e604a0cab9a8f3c054`.
- 22 unit tests and the full create-plan → start-workout → log-set → save-summary → view-progress UI test passed; no skipped tests.
- Device archive succeeded with Swift/Clang warnings treated as errors. The simulator build result reported zero errors, zero warnings and zero analyzer warnings; the archive log contained no compiler warnings.
- Real arm64 app and embedded WidgetKit/Live Activity extension packaged into an unsigned IPA. No provisioning profiles or code signatures are present. Expanded signing entitlements, Xcode version, source commit and SHA-256 accompany the artifact.
- IPA SHA-256 for that first build: `8f4669e396672d596b69ee7176154500ad487568d689712751300c22f3e6efa1`. A later build has its own hash and source-commit file.
- Inspected actual Arabic plan, workout and progress PNG screenshots from the small iPhone simulator. CI now also runs the flow on a large iPhone in dark mode with Western digits and exports screenshots plus accessibility hierarchies for both destinations.
- [Two-size passing run](https://github.com/ghghgh5052-beep/-/actions/runs/38017763411), source `13659c005d9cbf12304be0332ace2a8d6a7a5e79`: 23 tests passed on iPhone SE, plus the same UI flow on iPhone 16 Pro Max. Both build summaries reported zero warnings and errors. The exported Pro Max screenshots were visually inspected and confirmed dark appearance and Western digits; SE screenshots confirmed Arabic-Indic digits and light appearance.
- Xcode's `appintentsnltrainingprocessor` printed `Unable to parse extract.actionsdata` while succeeding. The packaged JSON was independently decoded and contains the start-workout intent, Arabic shortcut phrases and nonempty trained-language data. Packaging now validates these files explicitly. This confirms their presence, not successful Siri invocation on a signed device.
- Tests use `FITNESS_TESTING=1` and an isolated in-memory local store, avoiding entitlement-requiring CloudKit calls from the unsigned XCTest host. This does not change the production CloudKit configuration.
- Packaging queries app scheme settings and widget target settings separately. Both shipping targets are required before entitlement export; this avoids relying on `-showBuildSettings -scheme` to include implicit dependencies.

## Pending broader validation

- Review the latest run's compact/large screenshots and results, including chart-axis direction after removal of the redundant scale reversal.
- Additional accessibility text sizes, VoiceOver, Reduce Motion, every supported iPhone size, numeric field editing, calendar navigation and RTL swipe actions.
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

Until these device and broader QA gates pass, App Store-level polish, the no-crash/no-leak requirement, complete integration behavior and signed installability remain **unverified**. The native build/test results and zero compiler warnings listed above are verified separately.
