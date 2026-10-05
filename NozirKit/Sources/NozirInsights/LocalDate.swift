import Foundation

/// A day with no time and no zone, as the server writes it: `YYYY-MM-DD`
/// (`java.time.LocalDate`). Arithmetic runs on a fixed UTC Gregorian calendar,
/// so adding days never meets a daylight-saving gap; only `init(_:in:)` reads
/// the phone's calendar.
public struct LocalDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public init?(year: Int, month: Int, day: Int) {
        let parts = DateComponents(year: year, month: month, day: day)
        guard (1...9999).contains(year), parts.isValidDate(in: Self.utc) else { return nil }
        self.init(checked: year, month, day)
    }

    /// Exactly `YYYY-MM-DD` with ASCII digits; anything else is nil.
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { ("0"..."9").contains($0) } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The day `date` falls on in `calendar` (the phone's, for "today").
    public init(_ date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(checked: parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    private init(checked year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public var text: String {
        Self.padded(year, 4) + "-" + Self.padded(month, 2) + "-" + Self.padded(day, 2)
    }

    public var description: String { text }

    public func adding(days: Int) -> LocalDate {
        let moved = Self.utc.date(byAdding: .day, value: days, to: midnight) ?? midnight
        return LocalDate(moved, in: Self.utc)
    }

    /// ISO-8601: Monday is 1, Sunday is 7.
    public var isoWeekday: Int {
        let weekday = Self.utc.component(.weekday, from: midnight) // 1 = Sunday
        return (weekday + 5) % 7 + 1
    }

    /// The Monday of this day's ISO week.
    public var monday: LocalDate {
        adding(days: 1 - isoWeekday)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = LocalDate(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a YYYY-MM-DD day: \(text)")
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }

    private var midnight: Date {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    private static func padded(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
