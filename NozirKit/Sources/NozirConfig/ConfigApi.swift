import NozirNetworking

/// `GET /v1/config`. Unauthenticated on purpose: an app that cannot sign in
/// must still learn that it has to update and what the emergency number is.
public struct ConfigApi: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    public func fetch() async throws -> ServerConfig {
        try await client.send(
            // Short on purpose: the launch waits for this, and no answer falls
            // back to the cache or to no wall at all.
            ApiRequest(
                method: .get,
                path: "/v1/config",
                query: ["clientKind": "PARENT_IOS"],
                requiresAuth: false,
                timeout: 8
            ),
            as: ServerConfig.self
        )
    }
}
