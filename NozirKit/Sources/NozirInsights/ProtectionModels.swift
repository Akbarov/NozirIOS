import Foundation

/// `ProtectionLevel`: how much of the protection still works. A level this app
/// does not know reads as healthy (Android `UnknownLevelFallback`) — but only as
/// a floor: `resolving(unknown:hasFault:)` lifts it to degraded when the same
/// payload carries a fault. An invented fault would send a parent into the
/// child's settings for nothing; a hidden one would leave the phone unprotected.
public enum ProtectionLevel: String, Sendable, Decodable {
    case healthy = "HEALTHY"
    case degraded = "DEGRADED"
    case broken = "BROKEN"

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProtectionLevel(rawValue: raw) ?? .healthy
    }

    /// The level for a raw server string: a known one as written; an unknown
    /// one healthy, unless `hasFault` says the same payload shows a problem.
    static func resolving(_ raw: String, hasFault: Bool) -> ProtectionLevel {
        ProtectionLevel(rawValue: raw) ?? (hasFault ? .degraded : .healthy)
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
        let rawLevel = try container.decode(String.self, forKey: .level)
        let raw = (try? container.decodeIfPresent([LossyPermission].self, forKey: .permissions)) ?? []
        permissions = raw.compactMap { $0.raw?.permission }
        lastReportAt = (try? container.decodeIfPresent(Date.self, forKey: .lastReportAt))
        isStale = (try? container.decodeIfPresent(Bool.self, forKey: .isStale)) ?? false
        level = ProtectionLevel.resolving(rawLevel, hasFault: isStale || permissions.contains(where: \.needsFixing))
        manufacturer = (try? container.decodeIfPresent(String.self, forKey: .manufacturer)) ?? ""
        instructionKey = (try? container.decodeIfPresent(String.self, forKey: .instructionKey))
    }

    /// What "Yuborish" sends: every permission not granted, in the server's order.
    public var kindsToFix: [PermissionKind] {
        permissions.filter(\.needsFixing).map(\.kind)
    }
}

/// One element of `permissions`; one the app cannot read drops only itself.
private struct LossyPermission: Decodable {
    let raw: RawPermission?

    init(from decoder: any Decoder) throws {
        raw = try? RawPermission(from: decoder)
    }
}

/// One `PermissionStateDto` before the app decides whether it can use it. A
/// wrong-typed field reads as absent.
private struct RawPermission: Decodable {
    let kind: String?
    let status: String?
    let wasRevoked: Bool?
    let instructionKey: String?

    enum CodingKeys: String, CodingKey {
        case kind, status, wasRevoked, instructionKey
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try? container.decodeIfPresent(String.self, forKey: .kind)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        wasRevoked = try? container.decodeIfPresent(Bool.self, forKey: .wasRevoked)
        instructionKey = try? container.decodeIfPresent(String.self, forKey: .instructionKey)
    }

    var permission: ProtectionPermission? {
        guard let kind = kind.flatMap(PermissionKind.init(rawValue:)),
              let status = status.flatMap(PermissionStatus.init(rawValue:)) else { return nil }
        return ProtectionPermission(kind: kind, status: status, wasRevoked: wasRevoked ?? false, instructionKey: instructionKey)
    }
}
