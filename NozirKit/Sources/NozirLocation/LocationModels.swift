import Foundation

/// A point on the map. Not CoreLocation's type: that one is not Hashable and
/// this module has no reason to import a framework for two numbers.
public struct Coordinate: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Why the phone gave no position. A reason this app does not know reads as "no fix".
public enum LocationUnavailableReason: String, Sendable, Decodable {
    case locationOff = "LOCATION_OFF"
    case permissionDenied = "PERMISSION_DENIED"
    case noFix = "NO_FIX"

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LocationUnavailableReason(rawValue: raw) ?? .noFix
    }
}

/// `LocationSnapshotDto`: the last fix, or only the reason there is none.
/// `isStale` is the server's verdict (older than ~35 minutes); the app never
/// decides it.
public struct LocationSnapshot: Decodable, Equatable, Sendable {
    public let occurredAt: Date?
    public let latitude: Double?
    public let longitude: Double?
    public let accuracyMeters: Double?
    public let zoneId: UUID?
    public let zoneName: String?
    public let placeLabel: String?
    public let batteryPercent: Int?
    public let isStale: Bool
    public let unavailableReason: LocationUnavailableReason?
    public let unavailableAt: Date?

    public init(
        occurredAt: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        accuracyMeters: Double? = nil,
        zoneId: UUID? = nil,
        zoneName: String? = nil,
        placeLabel: String? = nil,
        batteryPercent: Int? = nil,
        isStale: Bool = false,
        unavailableReason: LocationUnavailableReason? = nil,
        unavailableAt: Date? = nil
    ) {
        self.occurredAt = occurredAt
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.zoneId = zoneId
        self.zoneName = zoneName
        self.placeLabel = placeLabel
        self.batteryPercent = batteryPercent
        self.isStale = isStale
        self.unavailableReason = unavailableReason
        self.unavailableAt = unavailableAt
    }

    /// Only when the server gave both halves.
    public var coordinate: Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}

/// What a parent sends for a zone (`SafeZoneBody`). `iconKey` is carried, not edited.
public struct SafeZoneDraft: Encodable, Equatable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var radiusMeters: Int
    public var notifyOnEnter: Bool
    public var notifyOnExit: Bool
    public var iconKey: String?

    public init(
        name: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Int,
        notifyOnEnter: Bool,
        notifyOnExit: Bool,
        iconKey: String? = nil
    ) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.notifyOnEnter = notifyOnEnter
        self.notifyOnExit = notifyOnExit
        self.iconKey = iconKey
    }
}

/// `SafeZoneDto`. `isActive` is false when the plan no longer includes zones:
/// the zone is kept, but nothing alerts on it.
public struct SafeZone: Decodable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let childId: UUID
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let radiusMeters: Int
    public let notifyOnEnter: Bool
    public let notifyOnExit: Bool
    public let iconKey: String?
    public let isActive: Bool

    public init(
        id: UUID,
        childId: UUID,
        name: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Int,
        notifyOnEnter: Bool,
        notifyOnExit: Bool,
        iconKey: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.childId = childId
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.notifyOnEnter = notifyOnEnter
        self.notifyOnExit = notifyOnExit
        self.iconKey = iconKey
        self.isActive = isActive
    }

    enum CodingKeys: String, CodingKey {
        case id = "zoneId"
        case childId, name, latitude, longitude, radiusMeters, notifyOnEnter, notifyOnExit, iconKey, isActive
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        childId = try container.decode(UUID.self, forKey: .childId)
        name = try container.decode(String.self, forKey: .name)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        radiusMeters = try container.decode(Int.self, forKey: .radiusMeters)
        notifyOnEnter = try container.decodeIfPresent(Bool.self, forKey: .notifyOnEnter) ?? true
        notifyOnExit = try container.decodeIfPresent(Bool.self, forKey: .notifyOnExit) ?? false
        iconKey = try container.decodeIfPresent(String.self, forKey: .iconKey)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }

    public var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    /// The zone as an editable form, exactly as stored.
    public var draft: SafeZoneDraft {
        SafeZoneDraft(
            name: name,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            notifyOnEnter: notifyOnEnter,
            notifyOnExit: notifyOnExit,
            iconKey: iconKey
        )
    }
}

/// `SosStatus`; a value this app does not know is `unknown` — never `active`,
/// so no "I have seen it" is offered for a state nobody understood.
public enum SosStatus: String, Sendable, Decodable {
    case active = "ACTIVE"
    case acknowledged = "ACKNOWLEDGED"
    case cancelledByChild = "CANCELLED_BY_CHILD"
    case resolved = "RESOLVED"
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SosStatus(rawValue: raw) ?? .unknown
    }
}

/// `SosAlertResponse`, the parts P15 shows. The position's time is its own
/// (`locationFixAt`), not the alarm's: "from 11 minutes ago" is honest.
public struct SosAlertDetail: Decodable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let childId: UUID
    public let childName: String?
    public let childPhoneE164: String?
    public let triggeredAt: Date
    public let status: SosStatus
    public let batteryPercent: Int?
    public let deviceOnline: Bool
    public let latitude: Double?
    public let longitude: Double?
    public let accuracyMeters: Double?
    public let locationFixAt: Date?
    public let placeLabel: String?
    public let acknowledgedAt: Date?
    public let cancelledAt: Date?

    public init(
        id: UUID,
        childId: UUID,
        childName: String? = nil,
        childPhoneE164: String? = nil,
        triggeredAt: Date,
        status: SosStatus = .active,
        batteryPercent: Int? = nil,
        deviceOnline: Bool = true,
        latitude: Double? = nil,
        longitude: Double? = nil,
        accuracyMeters: Double? = nil,
        locationFixAt: Date? = nil,
        placeLabel: String? = nil,
        acknowledgedAt: Date? = nil,
        cancelledAt: Date? = nil
    ) {
        self.id = id
        self.childId = childId
        self.childName = childName
        self.childPhoneE164 = childPhoneE164
        self.triggeredAt = triggeredAt
        self.status = status
        self.batteryPercent = batteryPercent
        self.deviceOnline = deviceOnline
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.locationFixAt = locationFixAt
        self.placeLabel = placeLabel
        self.acknowledgedAt = acknowledgedAt
        self.cancelledAt = cancelledAt
    }

    enum CodingKeys: String, CodingKey {
        case id, childId, childName, childPhoneE164, triggeredAt, status, batteryPercent, deviceOnline
        case latitude, longitude, accuracyMeters, locationFixAt, placeLabel, acknowledgedAt, cancelledAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        childId = try container.decode(UUID.self, forKey: .childId)
        childName = try container.decodeIfPresent(String.self, forKey: .childName)
        childPhoneE164 = try container.decodeIfPresent(String.self, forKey: .childPhoneE164)
        triggeredAt = try container.decode(Date.self, forKey: .triggeredAt)
        status = try container.decodeIfPresent(SosStatus.self, forKey: .status) ?? .unknown
        batteryPercent = try container.decodeIfPresent(Int.self, forKey: .batteryPercent)
        deviceOnline = try container.decodeIfPresent(Bool.self, forKey: .deviceOnline) ?? false
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        accuracyMeters = try container.decodeIfPresent(Double.self, forKey: .accuracyMeters)
        locationFixAt = try container.decodeIfPresent(Date.self, forKey: .locationFixAt)
        placeLabel = try container.decodeIfPresent(String.self, forKey: .placeLabel)
        acknowledgedAt = try container.decodeIfPresent(Date.self, forKey: .acknowledgedAt)
        cancelledAt = try container.decodeIfPresent(Date.self, forKey: .cancelledAt)
    }

    public var coordinate: Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}
