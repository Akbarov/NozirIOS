import Foundation

/// A wall-clock time in the family's zone, "HH:mm" on the wire.
public struct ClockTime: Hashable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public init?(_ text: String) {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    public var text: String {
        (hour < 10 ? "0" : "") + "\(hour):" + (minute < 10 ? "0" : "") + "\(minute)"
    }

    public var minutesSinceMidnight: Int {
        hour * 60 + minute
    }
}

/// `ScreenTimeLimitDto`. "Same every day" is not stored: it is school == weekend.
public struct ScreenTimeLimit: Codable, Equatable, Sendable {
    public var schoolDayMinutes: Int
    public var weekendMinutes: Int
    /// The ceiling on bonus minutes (P12). Not edited in 2a; carried through.
    public var maxDailyBonusMinutes: Int

    public init(schoolDayMinutes: Int, weekendMinutes: Int, maxDailyBonusMinutes: Int) {
        self.schoolDayMinutes = schoolDayMinutes
        self.weekendMinutes = weekendMinutes
        self.maxDailyBonusMinutes = maxDailyBonusMinutes
    }
}

/// `BedtimeScheduleDto`. The window normally crosses midnight, so an end
/// earlier than the start is expected.
public struct BedtimeSchedule: Codable, Equatable, Sendable {
    public var start: ClockTime
    public var end: ClockTime
    /// 0 means no warning before the window.
    public var windDownMinutes: Int
    /// ISO-8601 day numbers, 1 = Monday.
    public var activeDays: [Int]

    public init(start: ClockTime, end: ClockTime, windDownMinutes: Int, activeDays: [Int]) {
        self.start = start
        self.end = end
        self.windDownMinutes = windDownMinutes
        self.activeDays = activeDays
    }

    /// How long the phone stays closed.
    public var lengthMinutes: Int {
        (end.minutesSinceMidnight - start.minutesSinceMidnight + 24 * 60) % (24 * 60)
    }

    private enum CodingKeys: String, CodingKey {
        case startTime, endTime, windDownMinutes, activeDays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try Self.time(container, .startTime)
        end = try Self.time(container, .endTime)
        windDownMinutes = try container.decode(Int.self, forKey: .windDownMinutes)
        activeDays = try container.decode([Int].self, forKey: .activeDays)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start.text, forKey: .startTime)
        try container.encode(end.text, forKey: .endTime)
        try container.encode(windDownMinutes, forKey: .windDownMinutes)
        try container.encode(activeDays, forKey: .activeDays)
    }

    private static func time(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> ClockTime {
        let text = try container.decode(String.self, forKey: key)
        guard let time = ClockTime(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Not HH:mm: \(text)")
        }
        return time
    }
}

/// How often the child's phone reports unasked (`LocationTrackingDto`). Off
/// stops only the automatic reports: "where are they now" and SOS still take a
/// position. Values outside the choices are kept but select nothing on P12b.
public struct LocationTracking: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var intervalMinutes: Int
    public var zoneIntervalMinutes: Int
    public var moveMetres: Int

    public static let standard = LocationTracking(isEnabled: true, intervalMinutes: 10, zoneIntervalMinutes: 3, moveMetres: 100)
    public static let intervalChoices = [5, 10, 15, 30]
    public static let zoneIntervalChoices = [1, 3, 5]
    public static let moveChoices = [50, 100, 200]

    public init(isEnabled: Bool, intervalMinutes: Int, zoneIntervalMinutes: Int, moveMetres: Int) {
        self.isEnabled = isEnabled
        self.intervalMinutes = intervalMinutes
        self.zoneIntervalMinutes = zoneIntervalMinutes
        self.moveMetres = moveMetres
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, intervalMinutes, zoneIntervalMinutes, moveMetres
    }

    /// A server older than the tracking columns sends some or none of them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Self.standard
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? standard.isEnabled
        intervalMinutes = try container.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? standard.intervalMinutes
        zoneIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .zoneIntervalMinutes) ?? standard.zoneIntervalMinutes
        moveMetres = try container.decodeIfPresent(Int.self, forKey: .moveMetres) ?? standard.moveMetres
    }
}

/// `RuleSnapshotResponse`, the parts the app reads. `version` goes back as `If-Match`.
public struct RuleSnapshot: Decodable, Equatable, Sendable {
    public let version: Int64
    public let screenTime: ScreenTimeLimit
    public let bedtime: BedtimeSchedule
    public let locationTracking: LocationTracking

    public init(version: Int64, screenTime: ScreenTimeLimit, bedtime: BedtimeSchedule, locationTracking: LocationTracking = .standard) {
        self.version = version
        self.screenTime = screenTime
        self.bedtime = bedtime
        self.locationTracking = locationTracking
    }

    private enum CodingKeys: String, CodingKey {
        case version, screenTime, bedtime, locationTracking
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int64.self, forKey: .version)
        screenTime = try container.decode(ScreenTimeLimit.self, forKey: .screenTime)
        bedtime = try container.decode(BedtimeSchedule.self, forKey: .bedtime)
        locationTracking = try container.decodeIfPresent(LocationTracking.self, forKey: .locationTracking) ?? .standard
    }
}
