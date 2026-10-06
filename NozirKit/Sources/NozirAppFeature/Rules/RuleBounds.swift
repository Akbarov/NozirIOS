import Foundation
import NozirL10n

/// The bounds every rule slider moves in (Android `RuleMinuteRange`). Narrower
/// than the server allows on purpose: no slider offers taking the phone away
/// by accident, and a family talks about time in quarter hours.
enum RuleMinuteRange {
    static let step = 15
    static let dailyLimit = 30...360
    static let bonusCeiling = 0...120
    /// The same numbers as the bonus ceiling, and a separate rule. 0 means off.
    static let trustLadder = 0...120
    static let windDown = 15...60
    /// One app's daily time on P11 (Android `APP_DAILY_LIMIT`).
    static let appDailyLimit = 15...240
}

/// The nights a bedtime runs on, as ISO day numbers (1 = Monday).
enum RuleDays {
    /// The day flipped. The last night stays on: the server refuses an empty week,
    /// and a stray tap must not turn into a refused save.
    static func toggled(_ days: Set<Int>, _ day: Int) -> Set<Int> {
        guard (1...7).contains(day) else { return days }
        if days.contains(day) {
            return days.count > 1 ? days.subtracting([day]) : days
        }
        return days.union([day])
    }

    /// "Har kuni", or "Faol tunlar: Dushanba, Chorshanba".
    static func summary(_ days: Set<Int>, _ l10n: L10n) -> String {
        if days.count == 7 { return l10n.bedtimeDaysEveryNight }
        let names = days.sorted().compactMap { day in
            l10n.weekdayNames.indices.contains(day - 1) ? l10n.weekdayNames[day - 1] : nil
        }
        return l10n.bedtimeDaysSummary(names.joined(separator: l10n.bedtimeDaysSeparator))
    }
}
