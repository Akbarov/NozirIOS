import Foundation

/// What P19 draws about the family's plan (Android `SubscriptionState`).
public enum SubscriptionState: Equatable, Sendable {
    /// Never paid, no trial running (Android `None`).
    case free
    case trial(endsAt: Date?)
    /// Paid and running. `autoRenew` is always false with Click today.
    case active(planCode: String?, endsAt: Date?, autoRenew: Bool)
    /// The paid period ended; paying before `until` continues it from that day.
    case grace(planCode: String?, endedAt: Date?, until: Date?)
    /// A plan was held and lapsed: the server says FREE with a plan code.
    case expired(planCode: String, endedAt: Date?)

    /// Only money counts: a trial is not a payment landing.
    public var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    /// Android `SubscriptionMapper.toSubscriptionState`. `state` is the server's
    /// own word and wins; a missing or unknown word falls back to the older
    /// `tier`/`status` pair, so a server this build has not met still reads.
    static func read(
        tier: String?,
        status: String?,
        state: String?,
        planCode: String?,
        currentPeriodEnd: Date?,
        trialEndsAt: Date?,
        graceUntil: Date?,
        autoRenew: Bool
    ) -> SubscriptionState {
        let word = state.flatMap { knownStates.contains($0) ? $0 : nil }
        let isLegacyPaid = word == nil && tier == "PRO"
        if word == "TRIAL" {
            return .trial(endsAt: trialEndsAt)
        }
        if word == "GRACE" || (isLegacyPaid && status == "GRACE") {
            return .grace(planCode: planCode, endedAt: currentPeriodEnd, until: graceUntil)
        }
        if word == "PRO" || (isLegacyPaid && (status == "ACTIVE" || status == "GRACE")) {
            return .active(planCode: planCode, endsAt: currentPeriodEnd, autoRenew: autoRenew)
        }
        if let planCode {
            return .expired(planCode: planCode, endedAt: currentPeriodEnd)
        }
        return .free
    }

    /// Backend `SubscriptionState`.
    private static let knownStates: Set<String> = ["FREE", "TRIAL", "PRO", "GRACE"]
}
