import Foundation
import NozirNetworking

/// `/v1/parent/children/{childId}/protection` (backend `ProtectionController`).
public struct ProtectionApi: ProtectionService {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    static func path(_ childId: UUID) -> String {
        InsightsApi.childPath(childId) + "/protection"
    }

    public func status(childId: UUID) async throws -> ProtectionStatus {
        try await client.send(ApiRequest(method: .get, path: Self.path(childId)), as: ProtectionStatus.self)
    }

    public func sendInstructions(childId: UUID, kinds: [PermissionKind]) async throws {
        let request = try ApiRequest.post(Self.path(childId) + "/send-instructions", json: SendInstructionsBody(kinds: kinds))
        try await client.send(request)
    }
}

/// `SendInstructionsBody`.
private struct SendInstructionsBody: Encodable {
    let kinds: [PermissionKind]
}
