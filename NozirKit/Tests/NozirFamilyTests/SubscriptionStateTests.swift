import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirFamily

/// One subscription answer, read the way every screen reads it.
private func state(_ body: String) async throws -> SubscriptionState {
    let (api, _) = familyApi([.ok(body)])
    return try await api.subscription().state
}

@Suite struct SubscriptionStateTests {
    // Spec §4: the server's own word decides.
    @Test func eachStateTheServerNamesIsRead() async throws {
        #expect(try await state(subscriptionJSON(state: #""TRIAL""#, trialEndsAt: "2026-10-15T00:00:00Z"))
            == .trial(endsAt: moment("2026-10-15T00:00:00Z")))
        #expect(try await state(subscriptionJSON(state: #""TRIAL""#)) == .trial(endsAt: nil))
        #expect(try await state(subscriptionJSON(
            tier: "PRO", status: "GRACE", state: #""GRACE""#, planCode: "pro_monthly",
            currentPeriodEnd: "2026-10-07T00:00:00Z", graceUntil: "2026-10-10T00:00:00Z"
        )) == .grace(planCode: "pro_monthly", endedAt: moment("2026-10-07T00:00:00Z"), until: moment("2026-10-10T00:00:00Z")))
        #expect(try await state(subscriptionJSON(
            tier: "PRO", state: #""PRO""#, planCode: "pro_yearly", currentPeriodEnd: "2027-10-08T00:00:00Z"
        )) == .active(planCode: "pro_yearly", endsAt: moment("2027-10-08T00:00:00Z"), autoRenew: false))
        #expect(try await state(subscriptionJSON()) == .free)
        // The server never says EXPIRED as a state: FREE with a plan code is a lapsed plan.
        #expect(try await state(subscriptionJSON(status: "EXPIRED", planCode: "pro_monthly", currentPeriodEnd: "2026-09-01T00:00:00Z"))
            == .expired(planCode: "pro_monthly", endedAt: moment("2026-09-01T00:00:00Z")))
    }

    // Spec §4: a server without `state` is read from tier and status (Android's legacy rule).
    @Test func anOlderServerWithoutStateIsReadFromTierAndStatus() async throws {
        #expect(try await state(subscriptionJSON(tier: "PRO", status: "GRACE", state: "null", planCode: "pro_yearly"))
            == .grace(planCode: "pro_yearly", endedAt: nil, until: nil))
        #expect(try await state(subscriptionJSON(tier: "PRO", status: "ACTIVE", state: "null", planCode: "pro_yearly", autoRenew: "true"))
            == .active(planCode: "pro_yearly", endsAt: nil, autoRenew: true))
        #expect(try await state(subscriptionJSON(tier: "PRO", status: "EXPIRED", state: "null", planCode: "pro_yearly"))
            == .expired(planCode: "pro_yearly", endedAt: nil))
        #expect(try await state(subscriptionJSON(state: "null")) == .free)
    }

    // Review Focus 5: a word this app does not know is no word at all.
    @Test func aStateThisAppDoesNotKnowFallsBackToTierAndStatus() async throws {
        #expect(try await state(subscriptionJSON(tier: "PRO", status: "ACTIVE", state: #""FAMILY""#, planCode: "pro_yearly"))
            == .active(planCode: "pro_yearly", endsAt: nil, autoRenew: false))
        #expect(try await state(subscriptionJSON(state: #""FAMILY""#)) == .free)
        #expect(try await state(subscriptionJSON(tier: "PRO", status: "ACTIVE", state: "42", planCode: "pro_yearly")).isActive)
    }

    // Review Focus 5: an optional field of the wrong type is absent, never a failed screen.
    @Test func unreadableOptionalFieldsAreAbsent() async throws {
        let body = #"{"tier":"PRO","status":"ACTIVE","state":"PRO","planCode":"pro_yearly","currentPeriodEnd":"soon","autoRenew":"yes","activeChildId":"not-a-uuid"}"#
        let (api, _) = familyApi([.ok(body)])

        let subscription = try await api.subscription()

        #expect(subscription.state == .active(planCode: "pro_yearly", endsAt: nil, autoRenew: false))
        #expect(subscription.activeChildId == nil)
        #expect(subscription.isChildActive(aliId))
    }

    // 2a callers are untouched: the active child, and a body with nothing else in it.
    @Test func theActiveChildIsStillReadAndABareBodyIsFree() async throws {
        let (api, _) = familyApi([
            .ok(subscriptionJSON().replacingOccurrences(of: #""activeChildId":null"#, with: #""activeChildId":"\#(aliId.uuidString.lowercased())""#)),
            .ok(#"{"activeChildId":null}"#),
        ])

        let free = try await api.subscription()
        #expect(free.activeChildId == aliId)
        #expect(!free.isChildActive(UUID()))

        let bare = try await api.chooseActiveChild(aliId)
        #expect(bare.state == .free)
        #expect(bare.activeChildId == nil)
        #expect(Subscription(activeChildId: nil).state == .free)
    }

    @Test func onlyAPaidPeriodIsActive() {
        #expect(SubscriptionState.active(planCode: nil, endsAt: nil, autoRenew: false).isActive)
        #expect(!SubscriptionState.free.isActive)
        #expect(!SubscriptionState.trial(endsAt: nil).isActive)
        #expect(!SubscriptionState.grace(planCode: "pro_yearly", endedAt: nil, until: nil).isActive)
        #expect(!SubscriptionState.expired(planCode: "pro_yearly", endedAt: nil).isActive)
    }
}
