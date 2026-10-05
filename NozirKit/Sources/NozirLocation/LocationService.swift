import Foundation

/// Everything the location and SOS screens ask the server. `LocationApi` is
/// the real one; screen-model tests use a scripted fake.
public protocol LocationService: Sendable {
    /// A 404 (`ApiFailure.isNotFound`) means the phone has never reported.
    func location(of childId: UUID) async throws -> LocationSnapshot
    /// False: no paired phone or no way to wake it.
    func requestLocation(of childId: UUID) async throws -> Bool
    func safeZones(of childId: UUID) async throws -> [SafeZone]
    func createSafeZone(_ draft: SafeZoneDraft, for childId: UUID) async throws -> SafeZone
    func updateSafeZone(_ zoneId: UUID, _ draft: SafeZoneDraft) async throws -> SafeZone
    func deleteSafeZone(_ zoneId: UUID) async throws
    func sosAlert(_ sosId: UUID) async throws -> SosAlertDetail
    /// Settles the alarm on the server: stops the SMS escalation, tells the child's phone.
    func acknowledgeSos(_ sosId: UUID) async throws -> SosAlertDetail
}
