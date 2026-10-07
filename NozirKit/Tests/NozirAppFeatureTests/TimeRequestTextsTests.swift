import Foundation
import Testing
import NozirInsights
import NozirL10n
@testable import NozirAppFeature

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

@Suite struct PartialMinutesTests {
    // Spec §4.2: half, down to a multiple of five; nothing below five or at the whole ask.
    @Test(arguments: [(5, nil), (9, nil), (10, 5), (15, 5), (19, 5), (20, 10), (30, 15), (45, 20), (60, 30), (0, nil)] as [(Int, Int?)])
    func extraMinutesOfferRoughlyHalfInFives(requested: Int, offer: Int?) {
        #expect(PartialMinutes.of(extraTimeAsk(requested: requested)) == offer)
    }

    // A bedtime moves in the steps it was asked in: 30 halves to 15, 15 has no half.
    @Test(arguments: [(30, 15), (20, 15), (15, nil), (10, nil)] as [(Int, Int?)])
    func aBedtimeDelayOffersAQuarterOfAnHour(requested: Int, offer: Int?) {
        #expect(PartialMinutes.of(extraTimeAsk(kind: .bedtimeDelay, requested: requested)) == offer)
    }

    @Test func anUnknownKindOffersNothing() {
        #expect(PartialMinutes.of(extraTimeAsk(kind: .unknown("SCHOOL_TRIP"), requested: 60)) == nil)
    }
}

@Suite struct TimeRequestTextsTests {
    private let l10n = L10n(.uz)

    @Test func theRowSaysWhoAskedAndForWhat() {
        let minutes = extraTimeAsk(requested: 30)
        let delay = extraTimeAsk(kind: .bedtimeDelay, requested: 30)

        #expect(TimeRequestTexts.rowTitle(minutes, l10n) == l10n.homeExtraTimeTitle)
        #expect(TimeRequestTexts.rowBody(minutes, l10n) == l10n.homeExtraTimeBody("Ali", 30))
        #expect(TimeRequestTexts.rowTitle(delay, l10n) == l10n.homeBedtimeDelayTitle)
        #expect(TimeRequestTexts.rowBody(delay, l10n) == l10n.homeBedtimeDelayBody("Ali", 30))
    }

    @Test(arguments: [nil, "", "  \n"] as [String?])
    func aMissingOrBlankNameReadsAsTheChild(name: String?) {
        let minutes = extraTimeAsk(name: name, requested: 30)
        let delay = extraTimeAsk(name: name, kind: .bedtimeDelay, requested: 30)

        #expect(TimeRequestTexts.rowBody(minutes, l10n) == l10n.homeExtraTimeBodyUnnamed(30))
        #expect(TimeRequestTexts.rowBody(delay, l10n) == l10n.homeBedtimeDelayBodyUnnamed(30))
        #expect(TimeRequestTexts.header(minutes, l10n) == l10n.timeRequestHeaderUnnamed(30))
        #expect(TimeRequestTexts.header(delay, l10n) == l10n.timeRequestHeaderDelayUnnamed(30))
        #expect(TimeRequestTexts.note(minutes, l10n) == l10n.timeRequestNoteUnnamed)
    }

    // A parent who reads "30 minutes" and taps yes must not have moved a bedtime.
    @Test func theHeaderAndTheButtonsNeverMixTheTwoAsks() {
        let minutes = extraTimeAsk(requested: 30)
        let delay = extraTimeAsk(kind: .bedtimeDelay, requested: 30)

        #expect(TimeRequestTexts.header(minutes, l10n) == l10n.timeRequestHeader("Ali", 30))
        #expect(TimeRequestTexts.header(delay, l10n) == l10n.timeRequestHeaderDelay("Ali", 30))
        #expect(TimeRequestTexts.approveTitle(minutes, l10n) == l10n.timeRequestActionApprove(30))
        #expect(TimeRequestTexts.approveTitle(delay, l10n) == l10n.timeRequestActionApproveDelay(30))
        #expect(TimeRequestTexts.partialTitle(15, of: minutes, l10n) == l10n.timeRequestActionPartial(15))
        #expect(TimeRequestTexts.partialTitle(15, of: delay, l10n) == l10n.timeRequestActionPartialDelay(15))
        #expect(TimeRequestTexts.note(minutes, l10n) == l10n.timeRequestNote("Ali"))
        #expect(TimeRequestTexts.note(delay, l10n) == l10n.timeRequestDelayNote)
    }

    @Test func theTimeIsThePhonesClock() {
        #expect(TimeRequestTexts.headerMeta(extraTimeAsk(), l10n, calendar: utc) == l10n.timeRequestHeaderMeta("14:05"))
    }

    @Test func theChildsWordsAreQuotedAsWritten() {
        #expect(TimeRequestTexts.reason(extraTimeAsk(reason: "  Uy vazifasi tugadi \n"), l10n) == l10n.timeRequestReasonQuoted("Uy vazifasi tugadi"))
        #expect(TimeRequestTexts.reason(extraTimeAsk(reason: " "), l10n) == l10n.timeRequestReasonEmpty)
    }

    @Test func theContextIsTwoPlainFacts() {
        let used = l10n.timeRequestContextUsed(Durations.short(95, l10n))

        #expect(TimeRequestTexts.context(usedMinutesToday: 95, requestsInLastSevenDays: 3, l10n) == used + " " + l10n.timeRequestContextWeek(3))
        #expect(TimeRequestTexts.context(usedMinutesToday: 95, requestsInLastSevenDays: nil, l10n) == used)
        #expect(TimeRequestTexts.context(usedMinutesToday: nil, requestsInLastSevenDays: 1, l10n) == l10n.timeRequestContextWeekFirst)
        #expect(TimeRequestTexts.context(usedMinutesToday: nil, requestsInLastSevenDays: 0, l10n) == l10n.timeRequestContextWeekFirst)
        #expect(TimeRequestTexts.context(usedMinutesToday: nil, requestsInLastSevenDays: nil, l10n) == nil)
    }

    @Test func theAnswerSaysWhatWasGiven() {
        #expect(TimeRequestTexts.outcome(extraTimeAsk(status: .approved, granted: 15), l10n) == l10n.timeRequestDoneApproved(15))
        #expect(TimeRequestTexts.outcome(extraTimeAsk(requested: 30, status: .approved), l10n) == l10n.timeRequestDoneApproved(30))
        #expect(TimeRequestTexts.outcome(extraTimeAsk(status: .declined), l10n) == l10n.timeRequestDoneDeclined)
        #expect(TimeRequestTexts.outcome(extraTimeAsk(status: .expired), l10n) == l10n.timeRequestDoneExpired)
        #expect(TimeRequestTexts.outcome(extraTimeAsk(status: .pending), l10n) == nil)
        #expect(TimeRequestTexts.outcome(extraTimeAsk(status: .unknown("WITHDRAWN")), l10n) == nil)
    }

    @Test func aRefusalShowsItsReasonBackAndABlankOneNotAtAll() {
        #expect(TimeRequestTexts.decisionNote(extraTimeAsk(status: .declined, note: " Ertaga "), l10n) == l10n.timeRequestReasonQuoted("Ertaga"))
        #expect(TimeRequestTexts.decisionNote(extraTimeAsk(status: .declined, note: "  "), l10n) == nil)
        #expect(TimeRequestTexts.decisionNote(extraTimeAsk(status: .declined), l10n) == nil)
    }
}
