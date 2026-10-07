import Foundation
import Testing
@testable import NozirAppFeature

/// A wall clock a test moves by hand, forwards or back.
@MainActor
final class MovableClock {
    var now: Date

    init(_ now: Date = baseTime) {
        self.now = now
    }

    func advance(days: Double) {
        now = now.addingTimeInterval(days * 24 * 60 * 60)
    }
}

private let firstSeenKey = "review.firstSeenAt"
private let askedKey = "review.askedAt"
private let threeDays: TimeInterval = 3 * 24 * 60 * 60

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "ReviewGateTests.\(UUID().uuidString)")!
}

/// Spec D3, §4.2 (Android `ReviewGate`, `ReviewTiming`).
@MainActor
@Suite struct ReviewGateTests {
    @Test func theKeysAreTheSpecs() {
        #expect(ReviewGate.firstSeenKey == firstSeenKey)
        #expect(ReviewGate.askedKey == askedKey)
        #expect(ReviewGate.waitBeforeFirstAsk == threeDays)
    }

    @Test func theFirstSightingOnlyStartsTheClock() {
        let defaults = freshDefaults()
        let clock = MovableClock()
        let gate = ReviewGate(defaults: defaults, now: { clock.now })

        #expect(!gate.consumeIfDue())
        #expect(defaults.double(forKey: firstSeenKey) == baseTime.timeIntervalSince1970)
        #expect(defaults.object(forKey: askedKey) == nil)
    }

    @Test func lessThanThreeDaysIsNotYet() {
        let defaults = freshDefaults()
        let clock = MovableClock()
        let gate = ReviewGate(defaults: defaults, now: { clock.now })
        _ = gate.consumeIfDue()

        clock.now = baseTime.addingTimeInterval(threeDays - 1)

        #expect(!gate.consumeIfDue())
        #expect(defaults.object(forKey: askedKey) == nil)
    }

    @Test func threeDaysAsksAndRecordsItBeforeAnswering() {
        let defaults = freshDefaults()
        let clock = MovableClock()
        let gate = ReviewGate(defaults: defaults, now: { clock.now })
        _ = gate.consumeIfDue()

        clock.now = baseTime.addingTimeInterval(threeDays)

        #expect(gate.consumeIfDue())
        #expect(defaults.double(forKey: askedKey) == clock.now.timeIntervalSince1970)
        #expect(defaults.double(forKey: firstSeenKey) == baseTime.timeIntervalSince1970)
    }

    // Review Focus 4: once per install — not again later, not after a relaunch.
    @Test func neverAskedTwiceNotEvenAfterARelaunch() {
        let defaults = freshDefaults()
        let clock = MovableClock()
        let gate = ReviewGate(defaults: defaults, now: { clock.now })
        _ = gate.consumeIfDue()
        clock.advance(days: 3)

        #expect(gate.consumeIfDue())
        #expect(!gate.consumeIfDue())
        clock.advance(days: 30)
        #expect(!gate.consumeIfDue())
        let relaunched = ReviewGate(defaults: defaults, now: { clock.now })
        #expect(!relaunched.consumeIfDue())
    }

    // Review Focus 5: a clock moved back is "not yet", never "ask again", and
    // never moves the first sighting.
    @Test func aClockMovedBackIsNotYet() {
        let defaults = freshDefaults()
        let clock = MovableClock()
        let gate = ReviewGate(defaults: defaults, now: { clock.now })
        _ = gate.consumeIfDue()

        clock.advance(days: -10)

        #expect(!gate.consumeIfDue())
        #expect(defaults.double(forKey: firstSeenKey) == baseTime.timeIntervalSince1970)
        #expect(defaults.object(forKey: askedKey) == nil)
        clock.now = baseTime.addingTimeInterval(threeDays)
        #expect(gate.consumeIfDue())
    }

    @Test func aClockMovedBackAfterAskingNeverAsksAgain() {
        let defaults = freshDefaults()
        let clock = MovableClock()
        let gate = ReviewGate(defaults: defaults, now: { clock.now })
        _ = gate.consumeIfDue()
        clock.advance(days: 3)
        #expect(gate.consumeIfDue())

        clock.now = baseTime.addingTimeInterval(-30 * 24 * 60 * 60)
        #expect(!gate.consumeIfDue())
        clock.now = baseTime.addingTimeInterval(60 * 24 * 60 * 60)
        #expect(!gate.consumeIfDue())
    }
}
