import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirFamily

private let clickPage = "https://my.click.uz/services/pay?service_id=1&amount=7500"

@Suite struct BillingApiTests {
    // Spec §4 and Review Focus 5: only a plan the app can price honestly is offered.
    @Test func plansAreReadAsSomAndOnlyThoseTheAppCanPrice() async throws {
        let body = "[" + [
            planJSON(),
            planJSON(
                code: "pro_monthly", periodMonths: "1", priceMinorUnits: "100099",
                features: ["Bolaning joylashuvi", "Xavfsiz hududlar"],
                available: ["CLICK", "APPLE_PAY"], planned: ["PAYME", "SOMETHING_NEW"]
            ),
            planJSON(code: "free", tier: "FREE", priceMinorUnits: "0"),
            planJSON(code: "usd", currency: "USD"),
            planJSON(code: "half_year", periodMonths: "6"),
        ].joined(separator: ",") + "]"
        let (api, transport) = billingApi([.ok(body)])

        let plans = try await api.plans()

        #expect(plans == [
            SubscriptionPlan(
                code: "pro_yearly", period: .yearly, priceSom: 7_500,
                features: ["Bolaning joylashuvi"],
                availableChannels: [.click], plannedChannels: [.payme, .click, .uzum, .card]
            ),
            // Tiyin are cut, never rounded (Android `minorUnits / 100`).
            SubscriptionPlan(
                code: "pro_monthly", period: .monthly, priceSom: 1_000,
                features: ["Bolaning joylashuvi", "Xavfsiz hududlar"],
                availableChannels: [.click], plannedChannels: [.payme]
            ),
        ])
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/parent/subscription/plans")
    }

    // Review Focus 5: one plan the app cannot read never blanks the others.
    @Test func aPlanTheAppCannotReadIsLeftOut() async throws {
        let body = "[" + [
            planJSON(code: "broken", periodMonths: #""12""#),
            planJSON(code: "no_price", priceMinorUnits: "null"),
            planJSON(features: ["", "Bolaning joylashuvi"]),
        ].joined(separator: ",") + "]"
        let (api, _) = billingApi([.ok(body)])

        let plans = try await api.plans()

        #expect(plans.map(\.code) == ["pro_yearly"])
        #expect(plans.first?.features == ["Bolaning joylashuvi"])
    }

    // Global Constraints and Review Focus 2: one key per tap, never reused.
    @Test func aCheckoutCarriesAFreshIdempotencyKeyEveryTime() async throws {
        let (api, transport) = billingApi([
            .init(status: 201, body: checkoutJSON(clickPage)),
            .init(status: 201, body: checkoutJSON(clickPage)),
        ])

        let checkout = try await api.startCheckout(planCode: "pro_yearly", channel: .click)
        _ = try await api.startCheckout(planCode: "pro_yearly", channel: .click)

        #expect(checkout == SubscriptionCheckout(orderId: "5f2c1a0e-0000-4000-8000-000000000001", checkoutUrl: URL(string: clickPage)!))
        let requests = await transport.requests
        #expect(requests.count == 2)
        let first = try #require(requests.first)
        #expect(first.httpMethod == "POST")
        #expect(first.url?.path == "/v1/parent/subscription/checkout")
        #expect(first.jsonBody == ["planCode": "pro_yearly", "channel": "CLICK"])
        let keys = requests.compactMap { $0.value(forHTTPHeaderField: "Idempotency-Key") }
        #expect(keys.count == 2)
        #expect(keys.allSatisfy { UUID(uuidString: $0) != nil && $0 == $0.lowercased() })
        #expect(keys[0] != keys[1])
    }

    // Spec §4 and Review Focus 4: no web page, nothing to open.
    @Test(arguments: ["", "   ", "my.click.uz/services/pay", "javascript:alert(1)", "ftp://my.click.uz/pay", "https://"])
    func aCheckoutWithoutAPageToOpenIsUnreadable(url: String) async {
        let (api, _) = billingApi([.init(status: 201, body: checkoutJSON(url))])

        do {
            _ = try await api.startCheckout(planCode: "pro_yearly", channel: .click)
            Issue.record("expected an unreadable answer")
        } catch let failure as ApiFailure {
            guard case .decoding = failure else {
                Issue.record("unexpected \(failure)")
                return
            }
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func anUpperCaseSchemeIsStillAWebPage() async throws {
        let (api, _) = billingApi([.init(status: 201, body: checkoutJSON("HTTPS://my.click.uz/services/pay?service_id=1"))])

        let checkout = try await api.startCheckout(planCode: "pro_monthly", channel: .click)

        #expect(checkout.checkoutUrl.host() == "my.click.uz")
    }

    // Spec §3: a guardian is refused (403), a channel that is off is 503; one POST either way.
    @Test(arguments: [(403, "FORBIDDEN"), (503, "UPSTREAM_UNAVAILABLE")])
    func aRefusedCheckoutIsThrownAndNotRetried(status: Int, code: String) async {
        let (api, transport) = billingApi([.error(status, code: code), .init(status: 201, body: checkoutJSON(clickPage))])

        do {
            _ = try await api.startCheckout(planCode: "pro_yearly", channel: .click)
            Issue.record("expected a refusal")
        } catch let failure as ApiFailure {
            #expect(failure.code == ApiErrorCode(rawValue: code))
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(await transport.requests.count == 1)
    }
}
