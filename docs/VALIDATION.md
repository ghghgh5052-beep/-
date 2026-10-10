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
- The first native build contained 22 unit tests and one UI test. All 23 passed on iPhone SE (3rd generation), iOS 18.5; this is a historical result, not the current source count.
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
- Standard workout/image UI fixtures use `FITNESS_TESTING=1` and an isolated in-memory local store. The production-startup UI test instead opens a permanent local store through the real bootstrap path and relaunches the app; it does not prove a fresh installation on a signed device. This does not change production CloudKit configuration.
- Packaging queries app scheme settings and widget target settings separately. Both shipping targets are required before entitlement export; this avoids relying on `-showBuildSettings -scheme` to include implicit dependencies.

## Verified startup repair and version 1.1 gates

- [Startup-repair run](https://github.com/ghghgh5052-beep/-/actions/runs/38021944528), source `80ca60b3a1f70b1d9c68ea06254e835999d98f69`: 29 unit tests and two UI tests passed on SE; two UI tests passed on Pro Max. Both native build summaries reported zero errors, warnings and analyzer warnings. Ten portable tooling tests and three real Mach-O signature checks passed. These results precede the version 1.1 illustrations and ownership changes.
- The owner subsequently confirmed successful launch after manual signing and reported testing most app functions. This confirms the earlier launch repair; it does not establish signed CloudKit/HealthKit/widget acceptance or acceptance of a later binary.
- Version 1.1 removes the startup banner, shows truthful storage status in Settings, adds ownership only (`Coach : 3BIID - AB`) and provides 66 offline start/end illustration canvases. Real accounts/backend and social links are outside this release, as explicitly requested by the owner.
- Version 1.1 XCTest sources contain **32 unit tests and three UI tests**. The asset tests load all 66 images from the actual app bundle and verify permanent-ID association, rename stability and the absence of misleading custom-exercise fallbacks. UI tests cover opening, enlarging, reducing and closing the illustration, reading ownership/local status, reopening production storage, and viewing guidance while a workout is paused before resuming logging.
- Version 1.1 CI executes the 35-test complete suite on SE and the three UI tests on Pro Max: **38 native executions** are required. Portable asset checks validate exact PNG checksums/dimensions and 66 unique canvases. Successful execution is evidenced by the matching source commit, both native summaries, build diagnostics and IPA checksum delivered with the release; source/test presence alone is not a passing result.
- Illustration review is recorded separately from native execution, in [EXERCISE_ART.md](EXERCISE_ART.md). Actual screenshot inspection and signed-device acceptance remain separate from generation and static checks.

## Version 1.2 smart training gates

- Original deterministic offline workout generation, reviewed weight/repetition suggestions and estimated recovery for 12 muscle regions. Exact metadata covers all 66 built-in exercise IDs; archived completed history still informs recovery, while archived/custom movements cannot be generated.
- Additive SwiftData V3 `TrainingProfile`; V1/V2 remain unchanged. Complete JSON now exports format 2 and reads formats 1/2. A real V2 disk migration test preserves session, set, metric and PR UUID references.
- Current sources contain **58 unit tests and five UI tests**. New unit tests cover progression evidence, effort/failure/break rules, rounding, precise equipment, time budgets, unknown recovery, archived history, persistence/backup conflicts, atomic starts and protection of completed/warm-up sets when applying advice.
- New UI flows exercise an edited preview through start, reviewed advice, completed logging and recovery from actual saved data; cancellation creates no completed workout and retains exact equipment preferences. CI requires **63 tests on SE plus five on Pro Max: 68 native executions**. Source presence does not establish success; matching native summaries and the final IPA checksum must verify this release.
- No added signing capability, bundle identifier, dependency, account service or backend. The signed-device results of earlier versions do not establish acceptance of version 1.2.

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
