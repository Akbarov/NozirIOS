import Foundation

/// `ProtectionLevel`: how much of the protection still works. A level this app
/// does not know reads as healthy (Android `UnknownLevelFallback`): an invented
/// fault would send a parent into the child's settings for nothing.
public enum ProtectionLevel: String, Sendable, Decodable {
    case healthy = "HEALTHY"
    case degraded = "DEGRADED"
    case broken = "BROKEN"

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProtectionLevel(rawValue: raw) ?? .healthy
    }
}

/// `PermissionKind`, in the order the child app asks for them.
public enum PermissionKind: String, CaseIterable, Sendable, Encodable {
    case usageAccess = "USAGE_ACCESS"
    case overlay = "OVERLAY"
    case notifications = "NOTIFICATIONS"
    case location = "LOCATION"
    case battery = "BATTERY"
    case oemAutostart = "OEM_AUTOSTART"
}

/// `PermissionStatus`.
public enum PermissionStatus: String, Sendable {
    case granted = "GRANTED"
    case denied = "DENIED"
    case skipped = "SKIPPED"
}

/// `PermissionStateDto`, only ever built from a kind and a status this app
/// knows: one it cannot read is left out, never shown as broken.
public struct ProtectionPermission: Hashable, Sendable {
    public let kind: PermissionKind
    public let status: PermissionStatus
    /// Granted before and not now — the post-update case.
    public let wasRevoked: Bool
    public let instructionKey: String?

    public init(kind: PermissionKind, status: PermissionStatus, wasRevoked: Bool = false, instructionKey: String? = nil) {
        self.kind = kind
        self.status = status
        self.wasRevoked = wasRevoked
        self.instructionKey = instructionKey
    }

    /// Something a parent still has to do about (Android `needsFixing`).
    public var needsFixing: Bool {
        status != .granted
    }
}

/// `ProtectionStatusResponse`. Only `childId` is required; everything else is
/// read defensively, so a newer server never blanks the screen.
public struct ProtectionStatus: Decodable, Equatable, Sendable {
    public let childId: UUID
    public let level: ProtectionLevel
    /// In the order the child app asked for them.
    public let permissions: [ProtectionPermission]
    /// Nil when the phone never reported.
    public let lastReportAt: Date?
    public let isStale: Bool
    /// Lower case as the server stores it ("xiaomi"); "*" when no phone is paired.
    public let manufacturer: String
    public let instructionKey: String?

    public init(
        childId: UUID,
        level: ProtectionLevel = .healthy,
        permissions: [ProtectionPermission] = [],
        lastReportAt: Date? = nil,
        isStale: Bool = false,
        manufacturer: String = "",
        instructionKey: String? = nil
    ) {
        self.childId = childId
        self.level = level
        self.permissions = permissions
        self.lastReportAt = lastReportAt
        self.isStale = isStale
        self.manufacturer = manufacturer
        self.instructionKey = instructionKey
    }

    enum CodingKeys: String, CodingKey {
        case childId, level, permissions, lastReportAt, isStale, manufacturer, instructionKey
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        childId = try container.decode(UUID.self, forKey: .childId)
        level = try container.decodeIfPresent(ProtectionLevel.self, forKey: .level) ?? .healthy
        let raw = (try? container.decodeIfPresent([RawPermission].self, forKey: .permissions)) ?? []
        permissions = raw.compactMap(\.permission)
        lastReportAt = (try? container.decodeIfPresent(Date.self, forKey: .lastReportAt)) ?? nil
        isStale = (try? container.decodeIfPresent(Bool.self, forKey: .isStale)) ?? false
        manufacturer = (try? container.decodeIfPresent(String.self, forKey: .manufacturer)) ?? ""
        instructionKey = (try? container.decodeIfPresent(String.self, forKey: .instructionKey)) ?? nil
    }

    /// What "Yuborish" sends: every permission not granted, in the server's order.
    public var kindsToFix: [PermissionKind] {
        permissions.filter(\.needsFixing).map(\.kind)
    }
}

/// One `PermissionStateDto` before the app decides whether it can read it.
private struct RawPermission: Decodable {
    let kind: String?
    let status: String?
    let wasRevoked: Bool?
    let instructionKey: String?

    var permission: ProtectionPermission? {
        guard let kind = kind.flatMap(PermissionKind.init(rawValue:)),
              let status = status.flatMap(PermissionStatus.init(rawValue:)) else { return nil }
        return ProtectionPermission(kind: kind, status: status, wasRevoked: wasRevoked ?? false, instructionKey: instructionKey)
    }
}
