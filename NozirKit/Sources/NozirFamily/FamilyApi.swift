import Foundation
import NozirNetworking

/// `/v1/parent/*` for the family: children, their rules, pairing, the
/// subscription's active child and the parent's own record.
public struct FamilyApi: FamilyService {
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

    public func rules(of childId: UUID) async throws -> RuleSnapshot {
        try await client.send(ApiRequest(method: .get, path: Self.childPath(childId) + "/rules"), as: RuleSnapshot.self)
    }

    public func setScreenTime(_ limit: ScreenTimeLimit, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        let request = try ApiRequest.put(Self.childPath(childId) + "/rules/screen-time", json: limit, ifMatch: Self.entityTag(version))
        return try await client.send(request, as: RuleSnapshot.self)
    }

    public func setBedtime(_ bedtime: BedtimeSchedule, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        let request = try ApiRequest.put(Self.childPath(childId) + "/rules/bedtime", json: bedtime, ifMatch: Self.entityTag(version))
        return try await client.send(request, as: RuleSnapshot.self)
    }

    public func currentPairingCode(for childId: UUID) async throws -> PairingCode? {
        do {
            return try await client.send(ApiRequest(method: .get, path: Self.childPath(childId) + "/pairing-code"), as: PairingCode.self)
        } catch let failure as ApiFailure where failure.isNotFound {
            return nil
        }
    }

    /// Revokes the previous code; redeeming the new one retires the child's current phone.
    public func issuePairingCode(for childId: UUID) async throws -> PairingCode {
        try await client.send(ApiRequest(method: .post, path: Self.childPath(childId) + "/pairing-code"), as: PairingCode.self)
    }

    public func devices(of childId: UUID) async throws -> [ChildDevice] {
        try await client.send(ApiRequest(method: .get, path: Self.childPath(childId) + "/devices"), as: [ChildDevice].self)
    }

    public func subscription() async throws -> Subscription {
        try await client.send(ApiRequest(method: .get, path: "/v1/parent/subscription"), as: Subscription.self)
    }

    public func chooseActiveChild(_ childId: UUID) async throws -> Subscription {
        struct Body: Encodable {
            let childId: UUID
        }
        return try await client.send(try .put("/v1/parent/subscription/active-child", json: Body(childId: childId)), as: Subscription.self)
    }

    public func me() async throws -> ParentProfile {
        try await client.send(ApiRequest(method: .get, path: "/v1/parent/me"), as: ParentProfile.self)
    }

    public func updateLocale(_ locale: String) async throws -> ParentProfile {
        struct Body: Encodable {
            let locale: String
        }
        return try await client.send(try .patch("/v1/parent/me", json: Body(locale: locale)), as: ParentProfile.self)
    }

    /// `IfMatchVersion.format`: the version in double quotes.
    private static func entityTag(_ version: Int64) -> String {
        "\"\(version)\""
    }
}
