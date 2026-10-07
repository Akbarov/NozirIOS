import Foundation
import NozirNetworking

/// `/v1/parent/extra-time-requests` (backend `ChallengeController`).
public struct ExtraTimeApi: ExtraTimeService {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    static let path = "/v1/parent/extra-time-requests"

    public func pending() async throws -> [ExtraTimeRequest] {
        let request = ApiRequest(method: .get, path: Self.path, query: ["status": "PENDING"])
        return try await client.send(request, as: ExtraTimePage.self).items
    }

    public func decide(_ id: UUID, outcome: ExtraTimeOutcome, grantedMinutes: Int?, note: String?) async throws -> ExtraTimeRequest {
        let body = DecisionBody(outcome: outcome, grantedMinutes: grantedMinutes, note: note)
        let request = try ApiRequest.post(Self.path + "/\(id.uuidString.lowercased())/decision", json: body)
        return try await client.send(request, as: ExtraTimeRequest.self)
    }
}

/// `ExtraTimeRequestPage`. `nextCursor` is not read: the pending list is short.
private struct ExtraTimePage: Decodable {
    let items: [ExtraTimeRequest]

    enum CodingKeys: String, CodingKey {
        case items
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([ExtraTimeRequest].self, forKey: .items) ?? []
    }
}

/// `ExtraTimeDecisionBody`. The synthesised encoding leaves nil fields out.
private struct DecisionBody: Encodable {
    let outcome: ExtraTimeOutcome
    let grantedMinutes: Int?
    let note: String?
}
