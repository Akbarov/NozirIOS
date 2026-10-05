import Foundation
import NozirFamily
import NozirL10n

/// Minutes as Android `DurationText` writes them.
enum Durations {
    /// "2s 30d", "45d".
    static func short(_ minutes: Int, _ l10n: L10n) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        return hours == 0 ? l10n.durationShortMinutes(rest) : l10n.durationShortHoursMinutes(hours, rest)
    }

    /// "9 soat 0 daqiqa", "45 daqiqa".
    static func long(_ minutes: Int, _ l10n: L10n) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        return hours == 0 ? l10n.durationLongMinutes(rest) : l10n.durationLongHoursMinutes(hours, rest)
    }

    /// A slider's range, stretched to hold a value that came from elsewhere (a
    /// sibling's rules), so the slider never moves it without the parent touching it.
    static func range(_ base: ClosedRange<Int>, including value: Int) -> ClosedRange<Double> {
        Double(min(base.lowerBound, value))...Double(max(base.upperBound, value))
    }
}

extension ClockTime {
    /// The hour and minute a `DatePicker` shows.
    init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// Today at this time, for a `DatePicker`.
    func date(calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
