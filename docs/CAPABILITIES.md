# Capability and manual signing manifest

All identifiers are configurable in `Config/Identifiers.xcconfig`. **Replace the default namespace with identifiers you own before provisioning.** Changing a deployed CloudKit container later does not migrate the user's existing private cloud data.

## Targets and App IDs

| Target | Default bundle identifier | Product inside archive / IPA | Provisioning required |
| --- | --- | --- | --- |
| Fitness | `com.personal.Wateera` | `Payload/Fitness.app` | Yes, explicit iOS App ID |
| FitnessWidgets | `com.personal.Wateera.widgets` | `Payload/Fitness.app/PlugIns/FitnessWidgets.appex` | Yes, separate explicit iOS App ID |
| FitnessTests | `com.personal.Wateera.tests` | Test bundle, excluded from IPA | Simulator only; empty entitlements |
| FitnessUITests | `com.personal.Wateera.uitests` | Test runner, excluded from IPA | Simulator only; empty entitlements |

The widget extension also contains the Live Activity and Dynamic Island UI. **Live Activity has no additional bundle ID or separate entitlement.** App Intents and App Shortcuts are compiled into Fitness, with no separate extension or Siri entitlement. Apple Watch is deferred; no watch bundle ID, target or provisioning profile currently exists.

## Shared resources

| Resource | Default identifier | Registered for |
| --- | --- | --- |
| App Group | `group.com.personal.Wateera` | Fitness + FitnessWidgets |
| CloudKit container | `iCloud.com.personal.Wateera` | Fitness only, private database |

The extension reads a protected app-group JSON snapshot and a start-workout flag. It never opens SwiftData, reads HealthKit, or accesses CloudKit. The main database resides in Application Support inside the app sandbox; photos are external-storage SwiftData attributes in that private store. HealthKit is accessed only by Fitness.

## Exact source entitlements

`Config/Fitness.entitlements`:

| Entitlement | Value / build variable | Apple capability |
| --- | --- | --- |
| `com.apple.developer.healthkit` | `true` | HealthKit |
| `com.apple.developer.icloud-container-identifiers` | `[ $(CLOUDKIT_CONTAINER_IDENTIFIER) ]` | iCloud / CloudKit |
| `com.apple.developer.icloud-services` | `[ CloudKit ]` | iCloud / CloudKit |
| `com.apple.developer.icloud-container-environment` | `$(CLOUDKIT_ENVIRONMENT)`; default `Development` | CloudKit environment |
| `com.apple.security.application-groups` | `[ $(APP_GROUP_IDENTIFIER) ]` | App Groups |
| `aps-environment` | `$(APS_ENVIRONMENT)`; default `development` | Push Notifications, for CloudKit change delivery |

`Config/FitnessWidgets.entitlements`: only `com.apple.security.application-groups = [ $(APP_GROUP_IDENTIFIER) ]`.

`Config/FitnessTests.entitlements` and `Config/FitnessUITests.entitlements`: empty dictionaries. Tests never use real HealthKit or CloudKit data.

Provisioning/signing tools also supply `application-identifier`, `com.apple.developer.team-identifier`, `keychain-access-groups`, and `get-task-allow` as appropriate for your team/profile. Their team-prefixed values are intentionally not fabricated in source. Every requested entitlement must be allowed by the matching embedded provisioning profile. The unsigned artifact contains **no** provisioning profiles and **no** code signatures; entitlements become operative when you sign each executable.

## Capabilities without entitlement files

- Local UserNotifications: runtime permission, no push server, no local notification entitlement.
- Background Modes → Remote notifications: `UIBackgroundModes = [ remote-notification ]` in app Info.plist. Required for SwiftData CloudKit updates; APNs is Apple's infrastructure, not an application backend. No background audio or continuous background execution.
- ActivityKit: `NSSupportsLiveActivities = true`; no push token is requested and no ActivityKit remote-push capability. ActivityKit and WidgetKit run the UI/timers under iOS policies.
- LocalAuthentication: `NSFaceIDUsageDescription`, owner-authentication fallback to device passcode. No custom Keychain access or authentication backend.
- PhotosPicker: user selects individual photos through the system picker. No broad photo-library permission, camera entitlement or photo upload service.
- Files/share export/import: sandbox document picker and security-scoped file access. No iCloud Documents or ubiquity/KVS entitlement.
- HealthKit share/update descriptions are in Arabic. Reads body mass, steps and workouts for idempotence checks; writes completed traditional strength workouts, with pause/resume events. No clinical health records, background delivery or HealthKit access entitlement beyond `true`.
- URL scheme `wateera`: routes `today`, `active`, `progress` inside the app. No associated domains/universal links.

## Provisioning and re-signing checklist

1. Set your identifiers in the xcconfig and register both explicit App IDs.
2. Register the App Group and assign it to both IDs. Register the CloudKit container and assign it only to Fitness. Enable HealthKit and Push Notifications on Fitness.
3. Create the profiles used for your manual installation, including the device UDID when your distribution method requires it. Development profiles use the development APS environment; distribution profiles commonly use production. Match **both** `APS_ENVIRONMENT` and `CLOUDKIT_ENVIRONMENT` to the profile. A production CloudKit database needs its schema deployed using Apple's CloudKit Console after development schema initialization.
4. Build. CI exports `Fitness.resolved.entitlements` and `FitnessWidgets.resolved.entitlements` together with build settings. Confirm these values against your profiles; unsigned packaging cannot verify your team's provisioning rights.
5. Unzip the IPA. Embed the widget profile into `FitnessWidgets.appex/embedded.mobileprovision` and the app profile into `Fitness.app/embedded.mobileprovision`. Sign any nested frameworks if present, then the extension, then the app, each with its own profile-compatible entitlements. Do not use a single profile or a single entitlement dictionary for both bundles.
6. Verify signatures and expanded entitlements on **both** executables using `codesign --verify --strict` and `codesign -d --entitlements :-`. Repackage the same `Payload/` directory and install through your chosen manual signing/install tool.

The packaging script checks both device arm64 executables, bundle ID prefix, shared group, matching versions, extension embedding and absence of signatures/profiles. Successful packaging alone does not prove provisioning or installation; those require your real profiles and an iPhone.

## Apple references

[SwiftData CloudKit requirements](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices), [App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups), [Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), [HealthKit authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data), [Photos picker](https://developer.apple.com/documentation/photokit/bringing-photos-picker-to-your-swiftui-app).
