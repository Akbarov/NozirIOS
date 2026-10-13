import Foundation
import NozirFamily
import NozirNetworking
import NozirTestSupport

/// A bearer that never expires: these tests are about the family calls, not tokens.
struct FixedToken: AccessTokenProvider {
    func validAccessToken() async throws -> String { "acc" }
    func refreshAfterRejection(of token: String) async throws -> String { "acc" }
    func endSession(rejecting token: String) async {}
}

func familyApi(_ replies: [FakeTransport.Reply]) -> (FamilyApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: transport,
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5"),
        tokens: FixedToken()
    )
    return (FamilyApi(client: client), transport)
}

let aliId = UUID(uuidString: "0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01")!

/// `ChildResponse` exactly as the backend writes it.
func childJSON(
    id: UUID = aliId,
    name: String = "Ali",
    ageGroup: String = "STAR",
    pairingState: String = "NOT_PAIRED",
    phone: String = "null"
) -> String {
    """
    {"childId":"\(id.uuidString.lowercased())","displayName":"\(name)","birthYear":2015,\
    "ageGroup":"\(ageGroup)","ageGroupIsOverridden":false,"avatarKey":"teal","phoneE164":\(phone),\
    "pairingState":"\(pairingState)","createdAt":"2026-10-03T11:31:09.123456Z"}
    """
}

/// An instant written the way the backend writes it, whole seconds.
func moment(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

/// `SubscriptionResponse` as the backend writes it; a nil writes `null`.
/// `state` and `autoRenew` are raw JSON so a test can send what a newer or
/// broken server might.
func subscriptionJSON(
    tier: String = "FREE",
    status: String = "ACTIVE",
    state: String = #""FREE""#,
    planCode: String? = nil,
    currentPeriodEnd: String? = nil,
    trialEndsAt: String? = nil,
    graceUntil: String? = nil,
    autoRenew: String = "false"
) -> String {
    func field(_ value: String?) -> String {
        value.map { "\"\($0)\"" } ?? "null"
    }
    return #"{"familyId":"7d1e2a52-6a2f-4d8b-9a55-6f1b2a0c1d09","tier":"\#(tier)","status":"\#(status)","state":\#(state),"planCode":\#(field(planCode)),"channel":null,"currentPeriodEnd":\#(field(currentPeriodEnd)),"trialEndsAt":\#(field(trialEndsAt)),"graceUntil":\#(field(graceUntil)),"autoRenew":\#(autoRenew),"entitlements":[],"quotas":{"CHILDREN":1},"activeChildId":null}"#
}

func billingApi(_ replies: [FakeTransport.Reply]) -> (BillingApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: transport,
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5"),
        tokens: FixedToken()
    )
    return (BillingApi(client: client), transport)
}

/// `PlanResponse` as the backend writes it. `periodMonths` and
/// `priceMinorUnits` are raw JSON so a test can send a wrong type.
func planJSON(
    code: String = "pro_yearly",
    tier: String = "PRO",
    periodMonths: String = "12",
    priceMinorUnits: String = "750000",
    currency: String = "UZS",
    features: [String] = ["Bolaning joylashuvi"],
    available: [String] = ["CLICK"],
    planned: [String] = ["PAYME", "CLICK", "UZUM", "CARD"]
) -> String {
    let featureList = features.map { #"{"key":"feature","text":"\#($0)"}"# }.joined(separator: ",")
    func quoted(_ values: [String]) -> String {
        values.map { "\"\($0)\"" }.joined(separator: ",")
    }
    return #"{"code":"\#(code)","tier":"\#(tier)","periodMonths":\#(periodMonths),"priceMinorUnits":\#(priceMinorUnits),"currency":"\#(currency)","features":[\#(featureList)],"availableChannels":[\#(quoted(available))],"plannedChannels":[\#(quoted(planned))]}"#
}

/// `CheckoutResponse` with the given page.
func checkoutJSON(_ url: String) -> String {
    #"{"orderId":"5f2c1a0e-0000-4000-8000-000000000001","checkoutUrl":"\#(url)","channel":"CLICK","expiresAt":"2026-10-08T12:00:00Z"}"#
}
