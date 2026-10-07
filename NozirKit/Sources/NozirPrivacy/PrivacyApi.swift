import Foundation
import NozirNetworking

/// `/v1/parent/privacy/disclosure` and `/v1/parent/data-deletion-requests`.
/// The deletion request is never retried here: two taps on purpose are two
/// requests, a replay by the app is not.
public struct PrivacyApi: PrivacyService {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    public func disclosure() async throws -> PrivacyDisclosure {
        try await client.send(ApiRequest(method: .get, path: "/v1/parent/privacy/disclosure"), as: PrivacyDisclosure.self)
    }

    public func requestDeletion() async throws -> ErasureRequest {
        // `{}`: no childId — P20 is not a per-child control (spec D5).
        try await client.send(try .post("/v1/parent/data-deletion-requests", json: [String: String]()), as: ErasureRequest.self)
    }

    public func currentDeletion() async throws -> ErasureRequestStatus? {
        try await client.sendUnlessNoContent(
            ApiRequest(method: .get, path: "/v1/parent/data-deletion-requests/current"),
            as: ErasureRequestStatus.self
        )
    }
}
