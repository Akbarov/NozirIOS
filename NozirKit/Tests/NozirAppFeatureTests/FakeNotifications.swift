import Foundation
import NozirInsights
import NozirNetworking

/// Answers each call from its own queue, in order (an empty queue is a phone
/// with no connection), and records what was asked.
actor FakeNotifications: NotificationsService {
    struct PageAsk: Equatable, Sendable {
        let filter: NotificationFilter
        let cursor: String?
    }

    struct Script: Sendable {
        var pages: [Result<NotificationPage, ApiFailure>] = []
        var read: [Result<Void, ApiFailure>] = []
        var preferences: [Result<NotificationPreferences, ApiFailure>] = []
        var save: [Result<NotificationPreferences, ApiFailure>] = []
        /// Held once by the next `page` / `savePreferences` call, after its answer is taken.
        var pageGate: PauseGate?
        var saveGate: PauseGate?
    }

    private var script: Script
    /// "page", "read", "preferences", "save".
    private(set) var calls: [String] = []
    private(set) var pageAsks: [PageAsk] = []
    private(set) var readIds: [UUID] = []
    private(set) var saved: [NotificationPreferences] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    func add(_ change: @Sendable (inout Script) -> Void) {
        change(&script)
    }

    func page(filter: NotificationFilter, cursor: String?) async throws -> NotificationPage {
        calls.append("page")
        pageAsks.append(PageAsk(filter: filter, cursor: cursor))
        let answer: Result<NotificationPage, ApiFailure> = script.pages.isEmpty ? .failure(offline) : script.pages.removeFirst()
        let gate = script.pageGate
        script.pageGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }

    func markRead(_ id: UUID) async throws {
        calls.append("read")
        readIds.append(id)
        let answer: Result<Void, ApiFailure> = script.read.isEmpty ? .failure(offline) : script.read.removeFirst()
        try answer.get()
    }

    func preferences() async throws -> NotificationPreferences {
        calls.append("preferences")
        let answer: Result<NotificationPreferences, ApiFailure> = script.preferences.isEmpty ? .failure(offline) : script.preferences.removeFirst()
        return try answer.get()
    }

    func savePreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferences {
        calls.append("save")
        saved.append(preferences)
        let answer: Result<NotificationPreferences, ApiFailure> = script.save.isEmpty ? .failure(offline) : script.save.removeFirst()
        let gate = script.saveGate
        script.saveGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }
}

/// 2026-10-07T08:00:00Z (13:00 in Tashkent).
let notifiedAt = Date(timeIntervalSince1970: 1_791_360_000)

/// Ali's unread SOS by default, with no link.
func parentNotification(
    id: UUID = UUID(),
    type: NotificationType = .sosTriggered,
    tier: NotificationTier = .critical,
    key: String = "notification.sos.triggered",
    args: [String: String] = [:],
    childId: UUID? = UUID(),
    childName: String? = "Ali",
    deepLink: String? = nil,
    occurredAt: Date = notifiedAt,
    readAt: Date? = nil
) -> ParentNotification {
    ParentNotification(
        id: id,
        type: type,
        tier: tier,
        localisationKey: key,
        localisationArgs: args,
        childId: childId,
        childName: childName,
        deepLink: deepLink,
        occurredAt: occurredAt,
        readAt: readAt
    )
}

func notificationPage(_ items: [ParentNotification], cursor: String? = nil) -> NotificationPage {
    NotificationPage(items: items, nextCursor: cursor)
}

/// Every field set to something other than the defaults, a muted type this
/// app does not know among them, so a write that drops one shows.
func notificationPreferences(offlineAfter: Int = 360) -> NotificationPreferences {
    NotificationPreferences(
        dailyPushCap: 2,
        quietHoursStart: "22:00",
        quietHoursEnd: "07:00",
        mutedTypes: ["LIMIT_REACHED", "SOMETHING_NEW"],
        smsForCriticalEnabled: false,
        deviceOfflineAfterMinutes: offlineAfter
    )
}
