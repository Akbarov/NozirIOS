import Foundation

/// The child's asks for more time and the parent's answers (P17). `ExtraTimeApi`
/// is the real one; screen-model tests use a scripted fake.
public protocol ExtraTimeService: Sendable {
    /// Waiting asks, newest first (the server's order). There is no call for one ask.
    func pending() async throws -> [ExtraTimeRequest]
    /// One answer, sent once and never retried here. 409 `ALREADY_DECIDED` when
    /// it was answered elsewhere or expired; 404 when it is not this family's.
    func decide(_ id: UUID, outcome: ExtraTimeOutcome, grantedMinutes: Int?, note: String?) async throws -> ExtraTimeRequest
}
