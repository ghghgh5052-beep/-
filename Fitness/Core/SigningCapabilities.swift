import Foundation

/// Re-signing may remove restricted entitlements even when Info.plist still advertises them.
/// Read only this app's on-disk, thin arm64 executable. Unknown signature formats fail closed.
/// This is a capability preflight, not certificate/profile validation; iOS validates the signature.
struct SigningCapabilities {
    static let current: SigningCapabilities = {
        guard let url = Bundle.main.executableURL,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return SigningCapabilities(entitlements: [:])
        }
        return SigningCapabilities(entitlements: signedEntitlements(in: data) ?? [:])
    }()

    private let entitlements: [String: Any]

    init(entitlements: [String: Any]) { self.entitlements = entitlements }

    var hasHealthKit: Bool { entitlements["com.apple.developer.healthkit"] as? Bool == true }

    func allowsCloudKit(container identifier: String) -> Bool {
        guard !identifier.isEmpty, !identifier.contains("$("),
              let services = entitlements["com.apple.developer.icloud-services"] as? [String],
              services.contains("CloudKit"),
              let containers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String],
              containers.contains(identifier),
              let environment = entitlements["com.apple.developer.icloud-container-environment"] as? String,
              ["Development", "Production"].contains(environment) else { return false }
        return true
    }

    func allowsAppGroup(_ identifier: String) -> Bool {
        guard !identifier.isEmpty,
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else { return false }
        return groups.contains(identifier)
    }

    // Mach-O LC_CODE_SIGNATURE references a big-endian SuperBlob. XML entitlements use slot 5.
    // DER-only/fat/unreadable signatures are deliberately treated as unavailable, never inferred
    // from bundled .entitlements files or a provisioning profile's broader permission allowlist.
    static func signedEntitlements(in data: Data) -> [String: Any]? {
        guard data.count >= 32, word(data, at: 0, bigEndian: false) == 0xfeedfacf,
              word(data, at: 4, bigEndian: false) == 0x0100000c,
              let commandCount = word(data, at: 16, bigEndian: false), commandCount <= 4096,
              let commandBytes = word(data, at: 20, bigEndian: false),
              Int(commandBytes) <= data.count - 32 else { return nil }
        let commandsEnd = 32 + Int(commandBytes)
        var offset = 32
        for _ in 0..<Int(commandCount) {
            guard offset <= commandsEnd - 8,
                  let command = word(data, at: offset, bigEndian: false),
                  let size = word(data, at: offset + 4, bigEndian: false),
                  size >= 8, Int(size) <= commandsEnd - offset else { return nil }
            if command == 0x1d {
                guard size >= 16,
                      let start = word(data, at: offset + 8, bigEndian: false),
                      let count = word(data, at: offset + 12, bigEndian: false),
                      Int(start) >= commandsEnd, Int(start) <= data.count,
                      count >= 12, count <= 16 * 1024 * 1024,
                      Int(count) <= data.count - Int(start) else { return nil }
                return entitlementsBlob(in: data, start: Int(start), count: Int(count))
            }
            offset += Int(size)
        }
        return nil
    }

    private static func entitlementsBlob(in data: Data, start: Int, count: Int) -> [String: Any]? {
        guard word(data, at: start, bigEndian: true) == 0xfade0cc0,
              let length = word(data, at: start + 4, bigEndian: true),
              length >= 12, Int(length) <= count,
              let slots = word(data, at: start + 8, bigEndian: true),
              Int(slots) <= (Int(length) - 12) / 8 else { return nil }
        let indexEnd = 12 + Int(slots) * 8
        for index in 0..<Int(slots) {
            let entry = start + 12 + index * 8
            guard let type = word(data, at: entry, bigEndian: true),
                  let relative = word(data, at: entry + 4, bigEndian: true) else { return nil }
            guard type == 5 else { continue }
            guard Int(relative) >= indexEnd, Int(relative) <= Int(length) - 8 else { return nil }
            let blob = start + Int(relative)
            guard word(data, at: blob, bigEndian: true) == 0xfade7171,
                  let blobLength = word(data, at: blob + 4, bigEndian: true),
                  blobLength >= 8, Int(blobLength) <= Int(length) - Int(relative) else { return nil }
            let payload = data.subdata(in: (blob + 8)..<(blob + Int(blobLength)))
            return (try? PropertyListSerialization.propertyList(from: payload, options: [], format: nil)) as? [String: Any]
        }
        return nil
    }

    private static func word(_ data: Data, at offset: Int, bigEndian: Bool) -> UInt32? {
        guard offset >= 0, data.count >= 4, offset <= data.count - 4 else { return nil }
        var value: UInt32 = 0
        for index in 0..<4 {
            let shift = bigEndian ? (3 - index) * 8 : index * 8
            value |= UInt32(data[data.startIndex + offset + index]) << shift
        }
        return value
    }
}
