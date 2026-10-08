import Foundation
import NozirNetworking

/// `/v1/parent/notifications` and `/v1/parent/notification-preferences`
/// (backend `NotificationController`).
public struct NotificationsApi: NotificationsService {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    static let path = "/v1/parent/notifications"
    static let preferencesPath = "/v1/parent/notification-preferences"

    /// No `limit`: the server's default (20) is the page Android reads too.
    public func page(filter: NotificationFilter, cursor: String?) async throws -> NotificationPage {
        var query = ["filter": filter.rawValue]
        if let cursor {
            query["cursor"] = cursor
        }
        return try await client.send(ApiRequest(method: .get, path: Self.path, query: query), as: NotificationPage.self)
    }

    public func markRead(_ id: UUID) async throws {
        try await client.send(ApiRequest(method: .post, path: Self.path + "/\(id.uuidString.lowercased())/read"))
    }

    public func preferences() async throws -> NotificationPreferences {
        try await client.send(ApiRequest(method: .get, path: Self.preferencesPath), as: NotificationPreferences.self)
    }

    public func savePreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferences {
        try await client.send(try ApiRequest.put(Self.preferencesPath, json: preferences), as: NotificationPreferences.self)
    }
}
