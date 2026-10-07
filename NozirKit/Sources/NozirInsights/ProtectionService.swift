import Foundation

/// One child's protection and the "send the steps to the phone" action (P18).
/// `ProtectionApi` is the real one; screen-model tests use a scripted fake.
public protocol ProtectionService: Sendable {
    /// A child no longer in this family: 403 `NOT_YOUR_CHILD` (the backend's
    /// child-scope guard) or 404.
    func status(childId: UUID) async throws -> ProtectionStatus
    /// Pushes the fix steps for `kinds` to the child's phone (202, no body).
    /// Sent once and never retried here.
    func sendInstructions(childId: UUID, kinds: [PermissionKind]) async throws
}
