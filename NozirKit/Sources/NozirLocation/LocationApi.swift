import Foundation
import NozirNetworking

/// `/v1/parent/children/{id}/location`, `/safe-zones` and `/v1/parent/sos-alerts`
/// (backend `LocationController`, `SafeZoneController`, `SosController`).
public struct LocationApi: LocationService {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    static func childPath(_ id: UUID) -> String {
        "/v1/parent/children/\(id.uuidString.lowercased())"
    }

    static func zonePath(_ id: UUID) -> String {
        "/v1/parent/safe-zones/\(id.uuidString.lowercased())"
    }

    static func sosPath(_ id: UUID) -> String {
        "/v1/parent/sos-alerts/\(id.uuidString.lowercased())"
    }

    public func location(of childId: UUID) async throws -> LocationSnapshot {
        try await client.send(ApiRequest(method: .get, path: Self.childPath(childId) + "/location"), as: LocationSnapshot.self)
    }

    public func requestLocation(of childId: UUID) async throws -> Bool {
        struct Answer: Decodable {
            let asked: Bool
        }
        let request = ApiRequest(method: .post, path: Self.childPath(childId) + "/location/request")
        return try await client.send(request, as: Answer.self).asked
    }

    public func safeZones(of childId: UUID) async throws -> [SafeZone] {
        try await client.send(ApiRequest(method: .get, path: Self.childPath(childId) + "/safe-zones"), as: [SafeZone].self)
    }

    public func createSafeZone(_ draft: SafeZoneDraft, for childId: UUID) async throws -> SafeZone {
        try await client.send(try .post(Self.childPath(childId) + "/safe-zones", json: draft), as: SafeZone.self)
    }

    public func updateSafeZone(_ zoneId: UUID, _ draft: SafeZoneDraft) async throws -> SafeZone {
        try await client.send(try .put(Self.zonePath(zoneId), json: draft), as: SafeZone.self)
    }

    /// Never plan-gated on the server: a lapsed plan cannot keep a zone alive.
    public func deleteSafeZone(_ zoneId: UUID) async throws {
        try await client.send(ApiRequest(method: .delete, path: Self.zonePath(zoneId)))
    }

    public func sosAlert(_ sosId: UUID) async throws -> SosAlertDetail {
        try await client.send(ApiRequest(method: .get, path: Self.sosPath(sosId)), as: SosAlertDetail.self)
    }

    /// No Idempotency-Key (plan deviation E1): the endpoint is settle-once on
    /// the server, and the screen model guards double taps.
    public func acknowledgeSos(_ sosId: UUID) async throws -> SosAlertDetail {
        try await client.send(ApiRequest(method: .post, path: Self.sosPath(sosId) + "/acknowledge"), as: SosAlertDetail.self)
    }
}
