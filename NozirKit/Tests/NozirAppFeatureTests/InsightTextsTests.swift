import Foundation
import Testing
import NozirInsights
import NozirL10n
@testable import NozirAppFeature

private func entry(_ packageId: String, _ minutes: Int, name: String = "") -> AppUsageEntry {
    AppUsageEntry(packageId: packageId, displayName: name, minutes: minutes)
}

private func ymd(_ text: String) -> LocalDate {
    LocalDate(text)!
}

@Suite struct AppUsageFoldingTests {
    @Test func theFourLongestStayAndTheRestBecomeOthersLast() {
        let entries = [
            entry("a", 10), entry("b", 50), entry("c", 30), entry("d", 40), entry("e", 20), entry("f", 5),
        ]

        let folded = AppUsageFolding.folded(entries)

        #expect(folded.map(\.packageId) == ["b", "d", "c", "e", AppUsageEntry.otherAppsPackageId])
        #expect(folded.last?.minutes == 15)
    }

    @Test func theServersOwnOthersIsAddedToAndStaysLastHoweverLarge() {
        let entries = [entry(AppUsageEntry.otherAppsPackageId, 500, name: "Other"), entry("a", 10), entry("b", 20)]

        let folded = AppUsageFolding.folded(entries)

        #expect(folded == [entry("b", 20), entry("a", 10), entry(AppUsageEntry.otherAppsPackageId, 500, name: "Other")])
    }

    @Test func equalAppsKeepTheServersOrder() {
        let folded = AppUsageFolding.folded([entry("x", 10), entry("y", 10), entry("z", 10)])
        #expect(folded.map(\.packageId) == ["x", "y", "z"])
    }

    @Test func emptyOthersAreDropped() {
        let folded = AppUsageFolding.folded([entry("a", 10), entry(AppUsageEntry.otherAppsPackageId, 0)])
        #expect(folded == [entry("a", 10)])
    }

    @Test func aShareIsAWholePercentOfTheTotal() {
        #expect(AppUsageFolding.sharePercent(50, of: 75) == 66)
        #expect(AppUsageFolding.sharePercent(25, of: 75) == 33)
        #expect(AppUsageFolding.sharePercent(10, of: 0) == 0)
    }

    @Test func theChildsOwnLabelWinsUnlessItIsTheId() {
        #expect(AppUsageFolding.friendlyName(packageId: "uz.payme", reported: " Payme ") == "Payme")
        #expect(AppUsageFolding.friendlyName(packageId: "com.google.android.youtube", reported: "com.google.android.youtube") == "YouTube")
        #expect(AppUsageFolding.friendlyName(packageId: "org.telegram.messenger", reported: "") == "Telegram")
    }

    @Test func anUnknownIdIsTidied() {
        #expect(AppUsageFolding.friendlyName(packageId: "com.acme.some_game", reported: "") == "Some Game")
        #expect(AppUsageFolding.friendlyName(packageId: "com.acme.android.app", reported: "") == "Acme")
        #expect(AppUsageFolding.friendlyName(packageId: "com.app", reported: "") == "App")
        #expect(AppUsageFolding.friendlyName(packageId: "...", reported: "") == "...")
    }
}

@Suite struct InsightTextsTests {
    private let l10n = L10n(.uz)
    private let now = Date(timeIntervalSince1970: 1_791_200_000)

    @Test func elapsedTimeReadsInBands() {
        #expect(ElapsedTime(from: now.addingTimeInterval(-59), to: now) == .justNow)
        #expect(ElapsedTime(from: now.addingTimeInterval(30), to: now) == .justNow)
        #expect(ElapsedTime(from: now.addingTimeInterval(-60), to: now) == .minutes(1))
        #expect(ElapsedTime(from: now.addingTimeInterval(-3_599), to: now) == .minutes(59))
        #expect(ElapsedTime(from: now.addingTimeInterval(-3_600), to: now) == .hours(1))
        #expect(ElapsedTime(from: now.addingTimeInterval(-4 * 3_600 + 1), to: now) == .hours(3))
        #expect(ElapsedTime(from: now.addingTimeInterval(-4 * 3_600), to: now) == .stale(hours: 4))
    }

    @Test func elapsedTimeIsSaid() {
        #expect(ElapsedTime.justNow.text(l10n) == l10n.elapsedJustNow)
        #expect(ElapsedTime.minutes(5).text(l10n) == "5 daqiqa oldin")
        #expect(ElapsedTime.hours(2).text(l10n) == "2 soat oldin")
        #expect(ElapsedTime.stale(hours: 6).text(l10n) == l10n.elapsedStaleHours(6))
    }

    @Test func daysAreWrittenInTheParentsLanguage() {
        #expect(DateTexts.dayAndMonth(ymd("2026-10-05"), l10n) == "5-oktabr")
        #expect(DateTexts.dayAndMonth(ymd("2026-10-05"), L10n(.en)) == "October 5")
        #expect(DateTexts.weekdayAndDate(ymd("2026-10-05"), l10n) == "Dushanba, 5-oktabr")
        #expect(DateTexts.weekday(ymd("2026-10-11"), l10n) == "Yakshanba")
        #expect(DateTexts.shortWeekday(ymd("2026-10-11"), l10n) == "Ya")
    }

    @Test func aWeekNamesItsMonthOnceOrTwice() {
        #expect(DateTexts.weekRange(ymd("2026-10-05"), ymd("2026-10-11"), l10n) == l10n.dateRangeSameMonth(5, 11, "oktabr"))
        #expect(DateTexts.weekRange(ymd("2026-09-28"), ymd("2026-10-04"), l10n) == l10n.dateRangeAcrossMonths("28-sentabr", "4-oktabr"))
    }

    @Test func aTimeOfDayIsTheClockInThePhonesZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tashkent"))
        let moment = try #require(ISO8601DateFormatter().date(from: "2026-10-05T03:05:00Z"))

        #expect(DateTexts.timeOfDay(moment, calendar: calendar) == "08:05")
    }

    @Test func theDaySeparatorKeepsItsSpace() {
        #expect(L10n(.uz).weeklyChartDaySeparator == ", ")
        #expect(L10n(.ru).weeklyChartDaySeparator == ", ")
        #expect(L10n(.en).weeklyChartDaySeparator == ", ")
    }
}
