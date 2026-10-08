import Foundation
import NozirNetworking

/// `/v1/parent/subscription/plans` and `/checkout` (backend `BillingController`).
public struct BillingApi: BillingService {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    public func plans() async throws -> [SubscriptionPlan] {
        let raw = try await client.send(ApiRequest(method: .get, path: "/v1/parent/subscription/plans"), as: [RawPlan].self)
        return raw.compactMap(\.plan)
    }

    public func startCheckout(planCode: String, channel: PaymentChannel) async throws -> SubscriptionCheckout {
        struct Body: Encodable {
            let planCode: String
            let channel: PaymentChannel
        }
        var request = try ApiRequest.post("/v1/parent/subscription/checkout", json: Body(planCode: planCode, channel: channel))
        // One per tap (Android `UUID.randomUUID()` in the repository).
        request.idempotencyKey = UUID()
        return try await client.send(request, as: SubscriptionCheckout.self)
    }
}
