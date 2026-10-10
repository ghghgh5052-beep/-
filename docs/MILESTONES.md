# Milestones and release gates

This checkout contains implementation spanning M1–M5 and M6 test/build tooling. **M1's native build gate passed** in [Actions run 38017392175](https://github.com/ghghgh5052-beep/-/actions/runs/38017392175): 23 tests passed and a real unsigned IPA was produced for source commit `e6a58c5775052c396ccc62e604a0cab9a8f3c054`. That IPA also includes the implemented features from subsequent milestones for testing. Their device acceptance gates remain pending; source presence and simulator success do not prove HealthKit, CloudKit, background rest or manual signing.

| Milestone | Source implementation | Required release gate |
| --- | --- | --- |
| M1 | Versioned SwiftData V1→V2, migration plan, 66 Arabic exercises, 3 templates, Xcode project, CI, unsigned packaging | Compile + calculations/migration tests + actual IPA artifact |
| M2 | Editable/duplicate/archive plans, calendar, active anchored multiweek program, deload indication, fast set logging, prior sets, copy, groups/reorder/notes, pause/resume, persistent rest deadlines and calculators | Main-flow UI test + kill/relaunch + background rest on device + IPA |
| M3 | Epley/Brzycki charts, PR history, weekly volume/counts, weekly streak, muscle distribution, body metrics/moving average, local/private photos/comparison, goals | Correct charts/PRs + unit switching + photo lock/large text checks + IPA |
| M4 | Local workout/rest/weigh-in reminders, Arabic digits, RTL, theme/units/week start, biometrics/passcode, JSON/CSV import/export | Roundtrip tests + permission denial/retry + Arabic device inspection + IPA |
| M5 | HealthKit, private SwiftData CloudKit sync/dedup/status, home/lock widgets, Live Activity/Dynamic Island, App Intents | Real entitlements/profiles + Health permission/idempotence + two-device offline/cloud conflicts + widgets/intent/deadline verification + IPA |
| M6 | App/launch icon, Dynamic Type/VoiceOver labels, safe error paths, CI warning errors, documentation and artifact verification | Simulator size/OS matrix, Instruments/performance, signed install test, final IPA and complete validation evidence |

Each accepted milestone should use an immutable commit/tag and Actions artifact naming that includes the commit. CI runs on every push and manual dispatch. An artifact is produced only after tests pass. Intermediate source work must not be described as a tested milestone merely because it contains a feature.

Watch companion is phase 2 and excluded from all current targets.
