import Foundation

/// Everything the family screens ask the server. `FamilyApi` is the real one;
/// screen-model tests use a scripted fake.
public protocol FamilyService: Sendable {
    func children() async throws -> [Child]
    func child(_ id: UUID) async throws -> Child
    func createChild(_ child: ChildCreate) async throws -> Child
    func updateChild(_ id: UUID, _ update: ChildUpdate) async throws -> Child
    func removeChild(_ id: UUID) async throws
    func rules(of childId: UUID) async throws -> RuleSnapshot
    func setScreenTime(_ limit: ScreenTimeLimit, of childId: UUID, version: Int64) async throws -> RuleSnapshot
    func setBedtime(_ bedtime: BedtimeSchedule, of childId: UUID, version: Int64) async throws -> RuleSnapshot
    func setLocationTracking(_ tracking: LocationTracking, of childId: UUID, version: Int64) async throws -> RuleSnapshot
    func setTrustLadder(_ minutes: Int, of childId: UUID, version: Int64) async throws -> RuleSnapshot
    func bonus(of childId: UUID) async throws -> BonusConfig
    func setBonus(_ config: BonusConfig, of childId: UUID, version: Int64) async throws -> BonusConfig
    /// nil: no live code (404) — an answer, not a fault.
    func currentPairingCode(for childId: UUID) async throws -> PairingCode?
    func issuePairingCode(for childId: UUID) async throws -> PairingCode
    func devices(of childId: UUID) async throws -> [ChildDevice]
    func subscription() async throws -> Subscription
    func chooseActiveChild(_ childId: UUID) async throws -> Subscription
    func me() async throws -> ParentProfile
    func updateLocale(_ locale: String) async throws -> ParentProfile
}
