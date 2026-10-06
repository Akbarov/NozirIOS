import Foundation
import Testing
import NozirL10n
@testable import NozirAppFeature

@MainActor
@Suite struct RuleBoundsTests {
    @Test func theLastNightStaysOn() {
        #expect(RuleDays.toggled([3], 3) == [3])
        #expect(RuleDays.toggled([1, 3], 3) == [1])
        #expect(RuleDays.toggled([1], 5) == [1, 5])
        #expect(RuleDays.toggled([1], 8) == [1])
        #expect(RuleDays.toggled([1], 0) == [1])
    }

    @Test func theNightsAreNamedAsOnP03b() {
        let l10n = L10n(.uz)
        let mondayAndFriday = [l10n.weekdayNames[0], l10n.weekdayNames[4]].joined(separator: l10n.bedtimeDaysSeparator)

        #expect(RuleDays.summary(Set(1...7), l10n) == l10n.bedtimeDaysEveryNight)
        #expect(RuleDays.summary([5, 1], l10n) == l10n.bedtimeDaysSummary(mondayAndFriday))
        #expect(NewChildRulesModel.daysSummary([5, 1], l10n) == RuleDays.summary([5, 1], l10n))
    }

    @Test func theSlidersMoveInQuarterHoursWithinAndroidsBounds() {
        #expect(RuleMinuteRange.step == 15)
        #expect(RuleMinuteRange.dailyLimit == 30...360)
        #expect(RuleMinuteRange.trustLadder == 0...120)
        #expect(RuleMinuteRange.bonusCeiling == 0...120)
        #expect(RuleMinuteRange.windDown == 15...60)
    }
}
