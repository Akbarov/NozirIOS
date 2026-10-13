import Foundation

/// Android `BillingPeriod`: the two cadences the app can price.
public enum BillingPeriod: Int, CaseIterable, Sendable {
    case monthly = 1
    case yearly = 12

    public var months: Int {
        rawValue
    }
}

/// Backend `PaymentChannel`. A channel this app does not know is left out.
public enum PaymentChannel: String, CaseIterable, Sendable, Encodable {
    case payme = "PAYME"
    case click = "CLICK"
    case uzum = "UZUM"
    case card = "CARD"
    case googlePlay = "GOOGLE_PLAY"
}

/// `PlanResponse`, only ever built for a PRO plan in UZS of one or twelve months.
public struct SubscriptionPlan: Equatable, Sendable {
    public let code: String
    public let period: BillingPeriod
    /// Whole soʻm, converted from tiyin once, here (Android `moneyFromMinorUnits`).
    public let priceSom: Int64
    /// The server's own sentences, in its order.
    public let features: [String]
    /// The channels that can take money now.
    public let availableChannels: [PaymentChannel]
    /// The channels being prepared, shown as labels while none is live.
    public let plannedChannels: [PaymentChannel]

    public init(
        code: String,
        period: BillingPeriod,
        priceSom: Int64,
        features: [String],
        availableChannels: [PaymentChannel],
        plannedChannels: [PaymentChannel]
    ) {
        self.code = code
        self.period = period
        self.priceSom = priceSom
        self.features = features
        self.availableChannels = availableChannels
        self.plannedChannels = plannedChannels
    }
}

/// `CheckoutResponse`: the payment order and the page that pays it. An answer
/// without an `http`/`https` page cannot be decoded, so it reaches the parent
/// as "unreadable answer" and nothing is opened.
public struct SubscriptionCheckout: Decodable, Equatable, Sendable {
    public let orderId: String
    public let checkoutUrl: URL

    public init(orderId: String, checkoutUrl: URL) {
        self.orderId = orderId
        self.checkoutUrl = checkoutUrl
    }

    private enum CodingKeys: String, CodingKey {
        case orderId, checkoutUrl
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orderId = (try? container.decodeIfPresent(String.self, forKey: .orderId)) ?? ""
        let raw = (try? container.decodeIfPresent(String.self, forKey: .checkoutUrl))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), !host.isEmpty
        else {
            throw DecodingError.dataCorruptedError(forKey: .checkoutUrl, in: container, debugDescription: "No web page to open")
        }
        checkoutUrl = url
    }
}

/// One `PlanResponse` before the app decides whether it can price it. Every
/// field is read on its own, so one plan of the wrong shape is left out
/// instead of failing the list.
struct RawPlan: Decodable {
    let code: String?
    let tier: String?
    let periodMonths: Int?
    let priceMinorUnits: Int64?
    let currency: String?
    let features: [String]
    let availableChannels: [PaymentChannel]
    let plannedChannels: [PaymentChannel]

    private enum CodingKeys: String, CodingKey {
        case code, tier, periodMonths, priceMinorUnits, currency, features, availableChannels, plannedChannels
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try? container.decodeIfPresent(String.self, forKey: .code)
        tier = try? container.decodeIfPresent(String.self, forKey: .tier)
        periodMonths = try? container.decodeIfPresent(Int.self, forKey: .periodMonths)
        priceMinorUnits = try? container.decodeIfPresent(Int64.self, forKey: .priceMinorUnits)
        currency = try? container.decodeIfPresent(String.self, forKey: .currency)
        let rawFeatures = (try? container.decodeIfPresent([RawFeature].self, forKey: .features)) ?? []
        features = rawFeatures.compactMap(\.text).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        availableChannels = Self.channels(try? container.decodeIfPresent([String].self, forKey: .availableChannels))
        plannedChannels = Self.channels(try? container.decodeIfPresent([String].self, forKey: .plannedChannels))
    }

    /// Android `toSubscriptionPlanOrNull`: the free tier is a state, not an
    /// offer; another currency would be divided wrongly; another cadence has
    /// no name on screen.
    var plan: SubscriptionPlan? {
        guard tier == "PRO", currency == "UZS",
              let code, let priceMinorUnits,
              let months = periodMonths, let period = BillingPeriod(rawValue: months)
        else { return nil }
        return SubscriptionPlan(
            code: code,
            period: period,
            priceSom: priceMinorUnits / 100,
            features: features,
            availableChannels: availableChannels,
            plannedChannels: plannedChannels
        )
    }

    private static func channels(_ raw: [String]?) -> [PaymentChannel] {
        (raw ?? []).compactMap(PaymentChannel.init(rawValue:))
    }
}

/// `PlanFeatureDto`; only the text is shown.
private struct RawFeature: Decodable {
    let text: String?

    private enum CodingKeys: String, CodingKey {
        case text
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try? container.decodeIfPresent(String.self, forKey: .text)
    }
}
