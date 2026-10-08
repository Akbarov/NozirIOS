import Foundation

/// What P19 asks beyond the subscription itself (which stays on
/// `FamilyService.subscription()`). `BillingApi` is the real one; screen-model
/// tests use a scripted fake.
public protocol BillingService: Sendable {
    /// The plans the app can price honestly, in the server's order.
    func plans() async throws -> [SubscriptionPlan]
    /// Opens one payment order and returns its page. Every call is a new
    /// order with a fresh `Idempotency-Key`, sent once and never retried here.
    /// OWNER only: a guardian gets 403 `FORBIDDEN`; a channel that is off, 503.
    func startCheckout(planCode: String, channel: PaymentChannel) async throws -> SubscriptionCheckout
}
