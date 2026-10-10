import Foundation
import XCTest
@testable import Fitness

final class SigningCapabilitiesTests: XCTestCase {
    private let container = "iCloud.com.personal.Wateera"
    private var validEntitlements: [String: Any] {
        ["com.apple.developer.icloud-services": ["CloudKit"],
         "com.apple.developer.icloud-container-identifiers": [container],
         "com.apple.developer.icloud-container-environment": "Development",
         "com.apple.developer.healthkit": true,
         "com.apple.security.application-groups": ["group.com.personal.Wateera"]]
    }

    func testCapabilitiesRequireTheSignedContainerAndExactPermissions() {
        let capabilities = SigningCapabilities(entitlements: validEntitlements)
        XCTAssertTrue(capabilities.allowsCloudKit(container: container))
        XCTAssertFalse(capabilities.allowsCloudKit(container: "iCloud.other"))
        XCTAssertFalse(capabilities.allowsCloudKit(container: "$(CLOUDKIT_CONTAINER_IDENTIFIER)"))
        XCTAssertTrue(capabilities.hasHealthKit)
        XCTAssertTrue(capabilities.allowsAppGroup("group.com.personal.Wateera"))
        XCTAssertFalse(capabilities.allowsAppGroup("group.other"))
        for key in ["com.apple.developer.icloud-services", "com.apple.developer.icloud-container-identifiers",
                    "com.apple.developer.icloud-container-environment"] {
            var missing = validEntitlements; missing.removeValue(forKey: key)
            XCTAssertFalse(SigningCapabilities(entitlements: missing).allowsCloudKit(container: container))
        }
    }

    func testMalformedOrRemovedEntitlementsDisableOnlyTheirIntegrations() {
        let empty = SigningCapabilities(entitlements: [:])
        XCTAssertFalse(empty.allowsCloudKit(container: container))
        XCTAssertFalse(empty.hasHealthKit)
        XCTAssertFalse(empty.allowsAppGroup("group.com.personal.Wateera"))
        var healthOnly: [String: Any] = ["com.apple.developer.healthkit": true]
        XCTAssertTrue(SigningCapabilities(entitlements: healthOnly).hasHealthKit)
        XCTAssertFalse(SigningCapabilities(entitlements: healthOnly).allowsCloudKit(container: container))
        healthOnly["com.apple.developer.healthkit"] = "true"
        XCTAssertFalse(SigningCapabilities(entitlements: healthOnly).hasHealthKit)
    }

    func testReadsEntitlementsFromTheCodeSignatureInsteadOfBuildConfiguration() throws {
        let binary = try executable(entitlements: validEntitlements)
        let parsed = try XCTUnwrap(SigningCapabilities.signedEntitlements(in: binary))
        XCTAssertTrue(SigningCapabilities(entitlements: parsed).allowsCloudKit(container: container))
        let stripped = try executable(entitlements: ["application-identifier": "TEAM.com.personal.Wateera"])
        let strippedEntitlements = try XCTUnwrap(SigningCapabilities.signedEntitlements(in: stripped))
        XCTAssertFalse(SigningCapabilities(entitlements: strippedEntitlements).allowsCloudKit(container: container))
    }

    func testTruncatedExecutableAndUnsignedHeaderAreSafe() throws {
        let binary = try executable(entitlements: validEntitlements)
        for length in 0..<binary.count {
            XCTAssertNil(SigningCapabilities.signedEntitlements(in: Data(binary.prefix(length))))
        }
        var unsigned = Data(repeating: 0, count: 32)
        put(0xfeedfacf, in: &unsigned, at: 0)
        put(0x0100000c, in: &unsigned, at: 4)
        XCTAssertNil(SigningCapabilities.signedEntitlements(in: unsigned))
    }

    func testInvalidCommandLengthsAndBlobOffsetsAreRejected() throws {
        let original = try executable(entitlements: validEntitlements)
        for offset in [16, 20, 36, 40, 44] {
            var corrupt = original; put(UInt32.max, in: &corrupt, at: offset)
            XCTAssertNil(SigningCapabilities.signedEntitlements(in: corrupt))
        }
        for offset in [52, 56, 64, 72] {
            var corrupt = original; put(UInt32.max, in: &corrupt, at: offset, bigEndian: true)
            XCTAssertNil(SigningCapabilities.signedEntitlements(in: corrupt))
        }
        var overlapping = original; put(0, in: &overlapping, at: 64, bigEndian: true)
        XCTAssertNil(SigningCapabilities.signedEntitlements(in: overlapping))
    }

    func testUnsupportedSignatureSlotOrInvalidPlistNeverEnablesCloudKit() throws {
        var derOnly = try executable(entitlements: validEntitlements)
        put(7, in: &derOnly, at: 60, bigEndian: true)
        XCTAssertNil(SigningCapabilities.signedEntitlements(in: derOnly))
        var badPlist = try executable(entitlements: validEntitlements)
        for offset in 76..<badPlist.count { badPlist[offset] = 0 }
        XCTAssertNil(SigningCapabilities.signedEntitlements(in: badPlist))
    }

    private func executable(entitlements: [String: Any]) throws -> Data {
        let xml = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
        var data = Data(repeating: 0, count: 76)
        put(0xfeedfacf, in: &data, at: 0)
        put(0x0100000c, in: &data, at: 4)
        put(2, in: &data, at: 12)
        put(1, in: &data, at: 16)
        put(16, in: &data, at: 20)
        put(0x1d, in: &data, at: 32)
        put(16, in: &data, at: 36)
        put(48, in: &data, at: 40)
        put(UInt32(28 + xml.count), in: &data, at: 44)
        put(0xfade0cc0, in: &data, at: 48, bigEndian: true)
        put(UInt32(28 + xml.count), in: &data, at: 52, bigEndian: true)
        put(1, in: &data, at: 56, bigEndian: true)
        put(5, in: &data, at: 60, bigEndian: true)
        put(20, in: &data, at: 64, bigEndian: true)
        put(0xfade7171, in: &data, at: 68, bigEndian: true)
        put(UInt32(8 + xml.count), in: &data, at: 72, bigEndian: true)
        data.append(xml)
        return data
    }

    private func put(_ value: UInt32, in data: inout Data, at offset: Int, bigEndian: Bool = false) {
        for index in 0..<4 {
            let shift = bigEndian ? (3 - index) * 8 : index * 8
            data[offset + index] = UInt8(truncatingIfNeeded: value >> shift)
        }
    }
}
