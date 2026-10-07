import Foundation
import NozirInsights
import NozirL10n

/// Android `ElapsedTimeOf.kt`: the age of a moment in the band a parent reads it in.
enum ElapsedTime: Equatable {
    case justNow
    case minutes(Int)
    case hours(Int)
    /// Four hours and more: a guess, not an answer.
    case stale(hours: Int)

    /// A moment in the future is a disagreeing clock, read as "just now".
    init(from moment: Date, to now: Date) {
        let seconds = Int(now.timeIntervalSince(moment))
        guard seconds >= 60 else {
            self = .justNow
            return
        }
        let minutes = seconds / 60
        guard minutes >= 60 else {
            self = .minutes(minutes)
            return
        }
        let hours = minutes / 60
        self = hours < 4 ? .hours(hours) : .stale(hours: hours)
    }

    func text(_ l10n: L10n) -> String {
        switch self {
        case .justNow: l10n.elapsedJustNow
        case .minutes(let minutes): l10n.elapsedMinutes(minutes)
        case .hours(let hours): l10n.elapsedHours(hours)
        case .stale(let hours): l10n.elapsedStaleHours(hours)
        }
    }
}

/// Android `UzbekDateText.kt`: days in the parent's language, not the phone's.
enum DateTexts {
    /// "5-oktabr", "October 5".
    static func dayAndMonth(_ date: LocalDate, _ l10n: L10n) -> String {
        l10n.dateDayMonth(date.day, monthName(date, l10n))
    }

    /// "Dushanba, 5-oktabr".
    static func weekdayAndDate(_ date: LocalDate, _ l10n: L10n) -> String {
        l10n.dateWeekdayAndDay(weekday(date, l10n), dayAndMonth(date, l10n))
    }

    /// "5–11 oktabr" or "28-sentabr – 4-oktabr".
    static func weekRange(_ start: LocalDate, _ end: LocalDate, _ l10n: L10n) -> String {
        if start.year == end.year, start.month == end.month {
            return l10n.dateRangeSameMonth(start.day, end.day, monthName(end, l10n))
        }
        return l10n.dateRangeAcrossMonths(dayAndMonth(start, l10n), dayAndMonth(end, l10n))
    }

    /// "14-oktabr 2026", "October 14, 2026".
    static func dayMonthAndYear(_ date: LocalDate, _ l10n: L10n) -> String {
        l10n.dateDayMonthYear(date.day, monthName(date, l10n), date.year)
    }

    static func weekday(_ date: LocalDate, _ l10n: L10n) -> String {
        l10n.weekdayNames[date.isoWeekday - 1]
    }

    static func shortWeekday(_ date: LocalDate, _ l10n: L10n) -> String {
        l10n.weekdayNamesShort[date.isoWeekday - 1]
    }

    /// "08:05" on the phone's clock.
    static func timeOfDay(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return twoDigits(parts.hour ?? 0) + ":" + twoDigits(parts.minute ?? 0)
    }

    private static func monthName(_ date: LocalDate, _ l10n: L10n) -> String {
        l10n.monthNames[date.month - 1]
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
