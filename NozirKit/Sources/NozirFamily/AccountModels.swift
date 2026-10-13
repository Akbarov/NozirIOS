import Foundation

/// `PairingCodeResponse`. The server only ever returns a live code, so the
/// state is CODE_ISSUED or APP_INSTALLED in practice; anything it does not
/// know reads as CODE_ISSUED (Android does the same).
public struct PairingCode: Decodable, Equatable, Sendable {
    public let code: String
    public let expiresAt: Date
    public let qrPayload: String
    public let state: PairingState

    public init(code: String, expiresAt: Date, qrPayload: String, state: PairingState) {
        self.code = code
        self.expiresAt = expiresAt
        self.qrPayload = qrPayload
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case code, expiresAt, qrPayload, state
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        qrPayload = try container.decodeIfPresent(String.self, forKey: .qrPayload) ?? ""
        state = (try? container.decode(PairingState.self, forKey: .state)) ?? .codeIssued
    }

    /// What the QR carries: the server's payload, or the bare code if it sent none.
    public var qrContent: String {
        qrPayload.isEmpty ? code : qrPayload
    }
}

/// `ChildDeviceResponse`, the parts the replace-the-phone question names.
public struct ChildDevice: Decodable, Equatable, Sendable {
    public let id: UUID
    public let manufacturer: String
    public let model: String
    public let isOnline: Bool

    public init(id: UUID, manufacturer: String, model: String, isOnline: Bool) {
        self.id = id
        self.manufacturer = manufacturer
        self.model = model
        self.isOnline = isOnline
    }

    private enum CodingKeys: String, CodingKey {
        case id = "deviceId"
        case manufacturer, model, isOnline
    }

    public var label: String {
        "\(manufacturer) \(model)"
    }
}

/// `SubscriptionResponse`: the child a free family keeps active (2a) and the
/// plan's state (P19). Every field is read defensively: one this app cannot
/// read is absent, never a failed screen.
public struct Subscription: Decodable, Equatable, Sendable {
    /// The child a free family keeps fully active; nil while every child is.
    public let activeChildId: UUID?
    public let state: SubscriptionState

    public init(activeChildId: UUID?, state: SubscriptionState = .free) {
        self.activeChildId = activeChildId
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case activeChildId, tier, status, state, planCode, currentPeriodEnd, trialEndsAt, graceUntil, autoRenew
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeChildId = try? container.decodeIfPresent(UUID.self, forKey: .activeChildId)
        state = SubscriptionState.read(
            tier: try? container.decodeIfPresent(String.self, forKey: .tier),
            status: try? container.decodeIfPresent(String.self, forKey: .status),
            state: try? container.decodeIfPresent(String.self, forKey: .state),
            planCode: try? container.decodeIfPresent(String.self, forKey: .planCode),
            currentPeriodEnd: try? container.decodeIfPresent(Date.self, forKey: .currentPeriodEnd),
            trialEndsAt: try? container.decodeIfPresent(Date.self, forKey: .trialEndsAt),
            graceUntil: try? container.decodeIfPresent(Date.self, forKey: .graceUntil),
            autoRenew: (try? container.decodeIfPresent(Bool.self, forKey: .autoRenew)) ?? false
        )
    }

    /// False means frozen: the phone keeps its last rules, but they cannot change.
    public func isChildActive(_ id: UUID) -> Bool {
        activeChildId == nil || activeChildId == id
    }
}

/// `ParentAccountResponse`, the parts P21 and P20 use.
public struct ParentProfile: Decodable, Equatable, Sendable {
    public let displayName: String?
    public let phoneE164: String?
    public let locale: String
    /// `ParentRole`: "OWNER" or "GUARDIAN". Kept a string, like `ParentAccount.role`;
    /// nil when the server did not say, which P20 reads as "not the owner".
    public let role: String?

    public init(displayName: String?, phoneE164: String?, locale: String, role: String? = nil) {
        self.displayName = displayName
        self.phoneE164 = phoneE164
        self.locale = locale
        self.role = role
    }
}
