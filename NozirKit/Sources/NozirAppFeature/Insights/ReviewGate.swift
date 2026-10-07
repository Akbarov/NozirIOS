import Foundation

/// Spec D3 (Android `ReviewGate` + `ReviewTiming`): the one chance to ask for
/// a store review, spent once per install and not in the first three days.
/// On disk because the question is about this install, not this launch: an
/// app that asked yesterday must not ask again because it was restarted.
/// Apple decides whether its sheet appears; nothing here learns what the
/// parent did, and there is no second attempt.
@MainActor
final class ReviewGate {
    static let firstSeenKey = "review.firstSeenAt"
    static let askedKey = "review.askedAt"
    static let waitBeforeFirstAsk: TimeInterval = 3 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let now: @MainActor () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping @MainActor () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
    }

    /// True at most once per install. The first call only starts the three
    /// days. Records the ask **before** answering yes, so two screens asking
    /// in the same moment cannot both be told yes. A clock behind the first
    /// sighting reads as "not yet", never as "ask again" (plan deviation L9:
    /// seconds since 1970).
    func consumeIfDue() -> Bool {
        let moment = now()
        let firstSeen = firstSeenAt(moment)
        guard defaults.object(forKey: Self.askedKey) == nil,
              moment >= firstSeen,
              moment.timeIntervalSince(firstSeen) >= Self.waitBeforeFirstAsk
        else { return false }
        defaults.set(moment.timeIntervalSince1970, forKey: Self.askedKey)
        return true
    }

    /// Written on the first call and never moved afterwards.
    private func firstSeenAt(_ moment: Date) -> Date {
        if let stored = defaults.object(forKey: Self.firstSeenKey) as? Double {
            return Date(timeIntervalSince1970: stored)
        }
        defaults.set(moment.timeIntervalSince1970, forKey: Self.firstSeenKey)
        return moment
    }
}
