import NozirNetworking

/// `/v1/auth`. Every call here except logout is made without a bearer.
public struct AuthApi: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    public func telegramStart() async throws -> TelegramLoginStart {
        try await client.send(
            ApiRequest(method: .post, path: "/v1/auth/telegram/start", requiresAuth: false),
            as: TelegramLoginStart.self
        )
    }

    func telegramVerify(code: String, deviceLabel: String) async throws -> ParentAuthResult {
        struct Body: Encodable {
            let code: String
            let deviceLabel: String
        }
        return try await client.send(
            try .post("/v1/auth/telegram/verify", json: Body(code: code, deviceLabel: deviceLabel), requiresAuth: false),
            as: ParentAuthResult.self
        )
    }

    public func refresh(_ refreshToken: String) async throws -> TokenPair {
        struct Body: Encodable {
            let refreshToken: String
        }
        return try await client.send(
            try .post("/v1/auth/token/refresh", json: Body(refreshToken: refreshToken), requiresAuth: false),
            as: TokenPair.self
        )
    }

    /// Revokes every refresh token this parent holds (`AuthController.logout`).
    public func logout() async throws {
        try await client.send(ApiRequest(method: .post, path: "/v1/auth/logout"))
    }
}
