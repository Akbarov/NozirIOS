import Foundation
import NozirFamily
import NozirL10n

/// The sentences of P09 and its rows, as Android writes them.
enum RuleTexts {
    /// After a save: the child's phone takes it at the next connection.
    static func saved(childName: String?, _ l10n: L10n) -> String {
        childName.map(l10n.rulesSavedNamed) ?? l10n.rulesSaved
    }

    static func limitNotice(childName: String?, _ l10n: L10n) -> String {
        childName.map(l10n.dailyLimitNoticeNamed) ?? l10n.dailyLimitNotice
    }

    /// "O'chiq" at zero, "+45d" otherwise.
    static func trustValue(_ minutes: Int, _ l10n: L10n) -> String {
        minutes == 0 ? l10n.trustLadderOffValue : l10n.trustLadderValue(Durations.short(minutes, l10n))
    }

    static func trustNote(_ minutes: Int, _ l10n: L10n) -> String {
        minutes == 0 ? l10n.trustLadderNoteOff : l10n.trustLadderNoteRungs(Durations.short(minutes, l10n))
    }

    static func bedtimeRange(_ bedtime: BedtimeSchedule, _ l10n: L10n) -> String {
        l10n.rulesTimeRange(bedtime.start.text, bedtime.end.text)
    }

    static func bonusRow(_ snapshot: RuleSnapshot, _ l10n: L10n) -> String {
        l10n.rulesLinkBonusCeiling(Durations.short(snapshot.screenTime.maxDailyBonusMinutes, l10n))
    }

    static func locationRow(_ tracking: LocationTracking, _ l10n: L10n) -> String {
        tracking.isEnabled ? l10n.rulesLinkLocationEvery(tracking.intervalMinutes) : l10n.locationTrackingOff
    }
}
