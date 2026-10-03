/// The two halves of signing in through the bot, as the screen sees them.
public protocol TelegramSignInService: Sendable {
    func start() async throws -> TelegramLoginStart
    func verify(code: String) async throws
}

public struct TelegramSignIn: TelegramSignInService {
    private let api: AuthApi
    private let store: any TokenStore
    /// `UIDevice.model` ("iPhone"), never the device's name: the name is personal.
    private let deviceLabel: String

    public init(api: AuthApi, store: any TokenStore, deviceLabel: String) {
        self.api = api
        self.store = store
        self.deviceLabel = deviceLabel
    }

    public func start() async throws -> TelegramLoginStart {
        try await api.telegramStart()
    }

    public func verify(code: String) async throws {
        let result = try await api.telegramVerify(code: code, deviceLabel: deviceLabel)
        try store.save(result.tokens)
    }
}
