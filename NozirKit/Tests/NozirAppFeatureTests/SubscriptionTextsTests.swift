import Foundation
import Testing
import NozirFamily
import NozirInsights
import NozirL10n
@testable import NozirAppFeature

/// 2026-10-14T20:00:00Z: already the 15th in Tashkent (UTC+5).
private let lateOnTheFourteenth = Date(timeIntervalSince1970: 1_792_008_000)

private let tashkent: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
    return calendar
}()

@Suite struct SubscriptionTextsTests {
    private let l10n = L10n(.uz)

    // Android `groupedByThousands`: a no-break space every three digits, never the locale's.
    @Test func pricesAreGroupedByThousandsWithANoBreakSpace() {
        #expect(SubscriptionTexts.grouped(0) == "0")
        #expect(SubscriptionTexts.grouped(999) == "999")
        #expect(SubscriptionTexts.grouped(1_000) == "1\u{00A0}000")
        #expect(SubscriptionTexts.grouped(149_000) == "149\u{00A0}000")
        #expect(SubscriptionTexts.grouped(1_234_567) == "1\u{00A0}234\u{00A0}567")
        #expect(SubscriptionTexts.grouped(-1_500) == "-1\u{00A0}500")
    }

    // Android `yearlySavingPercent`: a whole percent, half rounds up; nothing to claim is nil.
    @Test func theYearlySavingIsAWholePercent() {
        #expect(SubscriptionMath.yearlySavingPercent(yearlySom: 149_000, monthlySom: 19_900) == 38)
        #expect(SubscriptionMath.yearlySavingPercent(yearlySom: proYearly.priceSom, monthlySom: proMonthly.priceSom) == 38)
        #expect(SubscriptionMath.yearlySavingPercent(yearlySom: 597, monthlySom: 50) == 1)
        #expect(SubscriptionMath.yearlySavingPercent(yearlySom: 598, monthlySom: 50) == 0)
        #expect(SubscriptionMath.yearlySavingPercent(yearlySom: 12_000, monthlySom: 1_000) == nil)
        #expect(SubscriptionMath.yearlySavingPercent(yearlySom: 13_000, monthlySom: 1_000) == nil)
        #expect(SubscriptionMath.yearlySavingPercent(yearlySom: 7_500, monthlySom: 0) == nil)
    }

    // Android `monthlyEquivalent`: a year over twelve, to the nearest 100 soʻm (50 rounds up).
    @Test func theMonthlyEquivalentIsRoundedToAHundred() {
        #expect(SubscriptionMath.monthlyEquivalent(yearlySom: 149_000) == 12_400)
        #expect(SubscriptionMath.monthlyEquivalent(yearlySom: 7_500) == 600)
        #expect(SubscriptionMath.monthlyEquivalent(yearlySom: 7_794) == 700)
        #expect(SubscriptionMath.monthlyEquivalent(yearlySom: 7_793) == 600)
        #expect(SubscriptionTexts.monthlyEquivalent(yearlySom: 149_000, l10n) == l10n.subscriptionMonthlyEquivalent("12\u{00A0}400"))
    }

    // Spec §4: Click when it is live, else the first live channel, else none.
    @Test func clickIsPreferredThenTheFirstLiveChannel() {
        #expect(SubscriptionMath.payChannel(planFixture(.yearly, priceSom: 1, available: [.payme, .click])) == .click)
        #expect(SubscriptionMath.payChannel(planFixture(.yearly, priceSom: 1, available: [.uzum, .payme])) == .uzum)
        #expect(SubscriptionMath.payChannel(planFixture(.yearly, priceSom: 1, available: [])) == nil)
        #expect(SubscriptionMath.payChannel(nil) == nil)
    }

    @Test func everyChannelAndPeriodHasItsWord() {
        #expect(SubscriptionTexts.channelName(.payme, l10n) == l10n.paymentChannelPayme)
        #expect(SubscriptionTexts.channelName(.click, l10n) == l10n.paymentChannelClick)
        #expect(SubscriptionTexts.channelName(.uzum, l10n) == l10n.paymentChannelUzum)
        #expect(SubscriptionTexts.channelName(.card, l10n) == l10n.paymentChannelCard)
        #expect(SubscriptionTexts.channelName(.googlePlay, l10n) == l10n.paymentChannelGooglePlay)
        #expect(SubscriptionTexts.planName(.yearly, l10n) == l10n.subscriptionPlanYearly)
        #expect(SubscriptionTexts.planName(.monthly, l10n) == l10n.subscriptionPlanMonthly)
        #expect(SubscriptionTexts.priceUnit(.yearly, l10n) == l10n.subscriptionPriceUnitYear)
        #expect(SubscriptionTexts.priceUnit(.monthly, l10n) == l10n.subscriptionPriceUnitMonth)
        #expect(SubscriptionTexts.activePeriod(.yearly, l10n) == l10n.subscriptionActiveYearly)
        #expect(SubscriptionTexts.activePeriod(.monthly, l10n) == l10n.subscriptionActiveMonthly)
    }

    // Spec §6: a date when the server gave one, in the phone's calendar; the title otherwise.
    @Test func theStateLinesNameTheDayOrSayTheTitle() {
        let fifteenth = DateTexts.dayMonthAndYear(day("2026-10-15"), l10n)

        #expect(SubscriptionTexts.trialLine(endsAt: lateOnTheFourteenth, calendar: tashkent, l10n) == l10n.subscriptionTrialUntil(fifteenth))
        #expect(SubscriptionTexts.trialLine(endsAt: nil, calendar: tashkent, l10n) == l10n.subscriptionTrialTitle)
        #expect(SubscriptionTexts.graceLine(until: lateOnTheFourteenth, calendar: tashkent, l10n) == l10n.subscriptionGraceUntil(fifteenth))
        #expect(SubscriptionTexts.graceLine(until: nil, calendar: tashkent, l10n) == l10n.subscriptionGraceTitle)
        #expect(SubscriptionTexts.activeUntil(endsAt: lateOnTheFourteenth, calendar: tashkent, l10n) == l10n.subscriptionActiveUntil(fifteenth))
        #expect(SubscriptionTexts.activeUntil(endsAt: nil, calendar: tashkent, l10n) == l10n.subscriptionActiveNoEndDate)
        #expect(SubscriptionTexts.autoRenew(true, l10n) == l10n.subscriptionActiveAutoRenewOn)
        #expect(SubscriptionTexts.autoRenew(false, l10n) == l10n.subscriptionActiveAutoRenewOff)
    }

    @Test func thePayButtonNamesTheChannelAndTheGroupedPrice() {
        #expect(SubscriptionTexts.payTitle(channel: .click, priceSom: proYearly.priceSom, l10n)
            == l10n.subscriptionActionPayWith(l10n.paymentChannelClick, SubscriptionTexts.grouped(proYearly.priceSom)))
    }

    // Spec §7: the one new iOS key, in three languages.
    @Test func theOwnerOnlyNoteIsInEveryLanguage() {
        #expect(L10n(.uz).iosSubscriptionOwnerOnly == "Obunani faqat oila egasi sotib oladi.")
        #expect(L10n(.ru).iosSubscriptionOwnerOnly == "Подписку покупает только владелец семьи.")
        #expect(L10n(.en).iosSubscriptionOwnerOnly == "Only the family owner can buy the subscription.")
    }
}
