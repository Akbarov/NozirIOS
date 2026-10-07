import Foundation

/// Everything P20 asks the server. `PrivacyApi` is the real one; screen-model
/// tests use a scripted fake.
public protocol PrivacyService: Sendable {
    func disclosure() async throws -> PrivacyDisclosure
    /// The whole family (body `{}`). An owner only: a guardian gets 403. The
    /// server revokes every parent's session when it records the request.
    func requestDeletion() async throws -> ErasureRequest
    /// nil: no pending request (204).
    func currentDeletion() async throws -> ErasureRequestStatus?
}
