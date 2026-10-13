import Foundation
import NozirFamily
import NozirInsights
import NozirL10n

/// Android `YearlySavingPercent.kt`, `MonthlyEquivalent.kt` and
/// `SubscriptionUiState.payChannel`, figure for figure. The saving and the
/// per-month line are derived from the two prices, so they can never
/// contradict the prices printed beside them.
enum SubscriptionMath {
    /// How much less a year costs than twelve months, as a whole percent (half
    /// rounds up). Nil when there is nothing to claim: no monthly price, or a
    /// year that costs at least twelve months. The badge is then not drawn.
    static func yearlySavingPercent(yearlySom: Int64, monthlySom: Int64) -> Int? {
        let twelveMonths = monthlySom * Int64(BillingPeriod.yearly.months)
        guard twelveMonths > 0 else { return nil }
        let saved = twelveMonths - yearlySom
        guard saved > 0 else { return nil }
        return Int((saved * 100 + twelveMonths / 2) / twelveMonths)
    }

    /// A year over twelve, rounded to the nearest 100 soʻm: a way of comparing
    /// two prices, not a figure anyone is charged.
    static func monthlyEquivalent(yearlySom: Int64) -> Int64 {
        let months = Int64(BillingPeriod.yearly.months)
        let perMonth = (yearlySom + months / 2) / months
        return ((perMonth + 50) / 100) * 100
    }

    /// Click when it is live, otherwise the first channel that can take money;
    /// nil when none can, and the button then says payment is not ready.
    static func payChannel(_ plan: SubscriptionPlan?) -> PaymentChannel? {
        let live = plan?.availableChannels ?? []
        return live.first { $0 == .click } ?? live.first
    }
}

/// P19 in words (Android `SubscriptionContent`, `SubscriptionActiveCard`,
/// `BillingPeriodLabels`, `PaymentChannelLabel`, `GroupedThousands`). Dates
/// are the day in `calendar` (the phone's), written in the parent's language.
enum SubscriptionTexts {
    /// 149000 as "149 000" with a no-break space, so a price never wraps
    /// inside itself; the locale's separator is never used.
    static func grouped(_ amount: Int64) -> String {
        let digits = String(amount.magnitude)
        var groups: [Substring] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            groups.insert(digits[start..<end], at: 0)
            end = start
        }
        let joined = groups.joined(separator: "\u{00A0}")
        return amount < 0 ? "-" + joined : joined
    }

    /// Brand names, the same word in every language.
    static func channelName(_ channel: PaymentChannel, _ l10n: L10n) -> String {
        switch channel {
        case .payme: l10n.paymentChannelPayme
        case .click: l10n.paymentChannelClick
        case .uzum: l10n.paymentChannelUzum
        case .card: l10n.paymentChannelCard
        case .googlePlay: l10n.paymentChannelGooglePlay
        }
    }

    static func planName(_ period: BillingPeriod, _ l10n: L10n) -> String {
        switch period {
        case .yearly: l10n.subscriptionPlanYearly
        case .monthly: l10n.subscriptionPlanMonthly
        }
    }

    static func priceUnit(_ period: BillingPeriod, _ l10n: L10n) -> String {
        switch period {
        case .yearly: l10n.subscriptionPriceUnitYear
        case .monthly: l10n.subscriptionPriceUnitMonth
        }
    }

    /// "Yillik obuna": what a family that pays is told it holds.
    static func activePeriod(_ period: BillingPeriod, _ l10n: L10n) -> String {
        switch period {
        case .yearly: l10n.subscriptionActiveYearly
        case .monthly: l10n.subscriptionActiveMonthly
        }
    }

    static func trialLine(endsAt: Date?, calendar: Calendar, _ l10n: L10n) -> String {
        guard let endsAt else { return l10n.subscriptionTrialTitle }
        return l10n.subscriptionTrialUntil(date(endsAt, calendar, l10n))
    }

    static func graceLine(until: Date?, calendar: Calendar, _ l10n: L10n) -> String {
        guard let until else { return l10n.subscriptionGraceTitle }
        return l10n.subscriptionGraceUntil(date(until, calendar, l10n))
    }

    static func activeUntil(endsAt: Date?, calendar: Calendar, _ l10n: L10n) -> String {
        guard let endsAt else { return l10n.subscriptionActiveNoEndDate }
        return l10n.subscriptionActiveUntil(date(endsAt, calendar, l10n))
    }

    static func autoRenew(_ isOn: Bool, _ l10n: L10n) -> String {
        isOn ? l10n.subscriptionActiveAutoRenewOn : l10n.subscriptionActiveAutoRenewOff
    }

    /// "Click orqali toʻlash · 7 500 soʻm".
    static func payTitle(channel: PaymentChannel, priceSom: Int64, _ l10n: L10n) -> String {
        l10n.subscriptionActionPayWith(channelName(channel, l10n), grouped(priceSom))
    }

    /// "12 400 soʻm/oy hisobida", under the yearly price.
    static func monthlyEquivalent(yearlySom: Int64, _ l10n: L10n) -> String {
        l10n.subscriptionMonthlyEquivalent(grouped(SubscriptionMath.monthlyEquivalent(yearlySom: yearlySom)))
    }

    private static func date(_ instant: Date, _ calendar: Calendar, _ l10n: L10n) -> String {
        DateTexts.dayMonthAndYear(LocalDate(instant, in: calendar), l10n)
    }
}
