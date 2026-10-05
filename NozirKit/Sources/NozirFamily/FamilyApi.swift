import Foundation
import NozirNetworking

/// `/v1/parent/*` for the family: children, their rules, pairing, the
/// subscription's active child and the parent's own record.
public struct FamilyApi: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    static func childPath(_ id: UUID) -> String {
        "/v1/parent/children/\(id.uuidString.lowercased())"
    }

    public func children() async throws -> [Child] {
        try await client.send(ApiRequest(method: .get, path: "/v1/parent/children"), as: [Child].self)
    }

    public func child(_ id: UUID) async throws -> Child {
        try await client.send(ApiRequest(method: .get, path: Self.childPath(id)), as: Child.self)
    }

    public func createChild(_ child: ChildCreate) async throws -> Child {
        try await client.send(try .post("/v1/parent/children", json: child), as: Child.self)
    }

    public func updateChild(_ id: UUID, _ update: ChildUpdate) async throws -> Child {
        try await client.send(try .patch(Self.childPath(id), json: update), as: Child.self)
    }

    /// Irreversible on the server: unpairs the phone and deletes the history.
    public func removeChild(_ id: UUID) async throws {
        try await client.send(ApiRequest(method: .delete, path: Self.childPath(id)))
    }
}
