import Foundation

/// macOS-only build check. Never compiled into an iPhone target.
@main
struct SigningSmoke {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 5 else { throw Failure.invalidArguments }
        let binary = try Data(contentsOf: URL(fileURLWithPath: arguments[1]), options: .mappedIfSafe)
        let parsed = SigningCapabilities.signedEntitlements(in: binary)
        let capabilities = SigningCapabilities(entitlements: parsed ?? [:])
        let expected = arguments[2] == "full"
        guard capabilities.allowsCloudKit(container: arguments[3]) == expected,
              capabilities.hasHealthKit == expected,
              capabilities.allowsAppGroup(arguments[4]) == expected,
              !capabilities.allowsCloudKit(container: "iCloud.unregistered.other"),
              !capabilities.allowsAppGroup("group.unregistered.other") else {
            throw Failure.incorrectCapabilities
        }
        if expected && parsed == nil { throw Failure.missingEntitlements }
        print("Native signature preflight passed: \(arguments[2])")
    }

    enum Failure: Error { case invalidArguments, incorrectCapabilities, missingEntitlements }
}
