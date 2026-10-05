import Foundation
import Testing
@testable import NozirInsights

private func day(_ text: String) -> LocalDate {
    LocalDate(text)!
}

private func calendar(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

@Suite struct LocalDateTests {
    @Test func theServersTextReadsAndWritesBack() throws {
        let date = try #require(LocalDate("2026-10-05"))

        #expect(date.year == 2026)
        #expect(date.month == 10)
        #expect(date.day == 5)
        #expect(date.text == "2026-10-05")
        #expect(LocalDate(year: 2026, month: 1, day: 9)?.text == "2026-01-09")
    }

    @Test(arguments: ["2026-02-30", "2026-1-5", "20261005", "2026-13-01", "", "2026-10-05T00:00", "２０２６-10-05"])
    func anythingElseIsNotADate(text: String) {
        #expect(LocalDate(text) == nil)
    }

    @Test func daysCrossMonthsAndYears() {
        #expect(day("2026-12-30").adding(days: 3) == day("2027-01-02"))
        #expect(day("2026-03-01").adding(days: -1) == day("2026-02-28"))
        #expect(day("2028-03-01").adding(days: -1) == day("2028-02-29"))
    }

    @Test func weekdaysAreCountedFromMonday() {
        #expect(day("2026-10-05").isoWeekday == 1)
        #expect(day("2026-10-08").isoWeekday == 4)
        #expect(day("2026-10-11").isoWeekday == 7)
    }

    // Review Focus 3.
    @Test func mondayOfAnyDay() {
        #expect(day("2026-10-05").monday == day("2026-10-05"))
        #expect(day("2026-10-11").monday == day("2026-10-05"))
        #expect(day("2026-01-01").monday == day("2025-12-29"))
        #expect(day("2026-03-01").monday == day("2026-02-23"))
    }

    @Test func theDayDependsOnThePhonesZone() throws {
        let moment = try #require(ISO8601DateFormatter().date(from: "2026-10-04T20:00:00Z"))

        #expect(LocalDate(moment, in: calendar("Asia/Tashkent")) == day("2026-10-05"))
        #expect(LocalDate(moment, in: calendar("UTC")) == day("2026-10-04"))
    }

    @Test func daysCompareInCalendarOrder() {
        #expect(day("2026-09-30") < day("2026-10-01"))
        #expect(day("2025-12-31") < day("2026-01-01"))
        #expect(!(day("2026-10-05") < day("2026-10-05")))
    }

    @Test func jsonCarriesTheText() throws {
        struct Box: Codable, Equatable {
            let date: LocalDate
        }

        let box = try JSONDecoder().decode(Box.self, from: Data(#"{"date":"2026-10-05"}"#.utf8))
        #expect(box.date == day("2026-10-05"))
        let written = try String(decoding: JSONEncoder().encode(box), as: UTF8.self)
        #expect(written == #"{"date":"2026-10-05"}"#)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Box.self, from: Data(#"{"date":"5.10.2026"}"#.utf8))
        }
    }
}
