import Foundation

/// The family's notification history and its settings (P16). `NotificationsApi`
/// is the real one; screen-model tests use a scripted fake. Nothing here is
/// retried.
public protocol NotificationsService: Sendable {
    /// Newest first; `cursor` nil for the first page.
    func page(filter: NotificationFilter, cursor: String?) async throws -> NotificationPage
    /// 204; a row already read is not an error.
    func markRead(_ id: UUID) async throws
    func preferences() async throws -> NotificationPreferences
    /// A full replace; answers what the server stored (it clamps).
    func savePreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferences
}
