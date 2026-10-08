import Foundation
import NozirFamily
import NozirNetworking

/// What one checkout asked for.
struct CheckoutCall: Equatable, Sendable {
    let planCode: String
    let channel: PaymentChannel
}

/// Answers the plans and each checkout from their own queue, in order (an
/// empty queue is a phone with no connection), and records what was asked.
actor FakeBilling: BillingService {
    struct Script: Sendable {
        var plans: [Result<[SubscriptionPlan], ApiFailure>] = []
        var checkout: [Result<SubscriptionCheckout, ApiFailure>] = []
        /// Held once by the next `plans` / `startCheckout` call, after its answer is taken.
        var plansGate: PauseGate?
        var checkoutGate: PauseGate?
    }

    private var script: Script
    /// "plans", "checkout".
    private(set) var calls: [String] = []
    private(set) var checkouts: [CheckoutCall] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    func add(_ change: @Sendable (inout Script) -> Void) {
        change(&script)
    }

    func plans() async throws -> [SubscriptionPlan] {
        calls.append("plans")
        let answer: Result<[SubscriptionPlan], ApiFailure> = script.plans.isEmpty ? .failure(offline) : script.plans.removeFirst()
        let gate = script.plansGate
        script.plansGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }

    func startCheckout(planCode: String, channel: PaymentChannel) async throws -> SubscriptionCheckout {
        calls.append("checkout")
        checkouts.append(CheckoutCall(planCode: planCode, channel: channel))
        let answer: Result<SubscriptionCheckout, ApiFailure> = script.checkout.isEmpty ? .failure(offline) : script.checkout.removeFirst()
        let gate = script.checkoutGate
        script.checkoutGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }
}

/// A PRO plan as the server lists it; the code follows the period
/// (`V18__plan_catalogue.sql`).
func planFixture(
    _ period: BillingPeriod,
    priceSom: Int64,
    available: [PaymentChannel] = [.click],
    planned: [PaymentChannel] = [.payme, .click, .uzum, .card],
    features: [String] = ["Bolaning joylashuvi", "Har kungi AI xulosa"]
) -> SubscriptionPlan {
    SubscriptionPlan(
        code: period == .yearly ? "pro_yearly" : "pro_monthly",
        period: period,
        priceSom: priceSom,
        features: features,
        availableChannels: available,
        plannedChannels: planned
    )
}

/// The two plans as the test server sells them. Tests read every price from
/// here, never from a literal (spec §3).
let proYearly = planFixture(.yearly, priceSom: 7_500)
let proMonthly = planFixture(.monthly, priceSom: 1_000, features: ["Bolaning joylashuvi"])

let clickCheckout = SubscriptionCheckout(
    orderId: "5f2c1a0e-0000-4000-8000-000000000001",
    checkoutUrl: URL(string: "https://my.click.uz/services/pay?service_id=1&amount=7500")!
)

func familySubscription(_ state: SubscriptionState) -> Subscription {
    Subscription(activeChildId: nil, state: state)
}
