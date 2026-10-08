import Foundation
import Observation
import NozirInsights
import NozirNetworking

/// P16 (Android `NotificationsViewModel`): the family's whole history, a page
/// at a time, "Hammasi" or "Muhim"; a tapped row is read at once and the
/// server told behind it; and the "telefon jim qolsa" threshold. Nothing is
/// retried. Every load bumps a generation: a filter switch or a refresh drops
/// any older answer, including a "Yana" in flight.
@MainActor
@Observable
final class NotificationsModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// The first page failed with nothing on screen.
        case failed(UserMessage)
    }

    private(set) var filter: NotificationFilter = .all
    private(set) var items: [ParentNotification] = []
    private(set) var nextCursor: String?
    private(set) var phase: Phase = .loading
    /// A list is on screen but the last refresh found no connection.
    private(set) var isOffline = false
    private(set) var isLoadingMore = false
    /// Under the list: a "Yana" that failed, or a refresh fault that is not "offline".
    private(set) var inlineMessage: UserMessage?
    /// Nil until read; the card is not drawn without it.
    private(set) var preferences: NotificationPreferences?
    /// The preset just chosen, while its write is in flight.
    private(set) var pendingOfflineMinutes: Int?
    /// A failed settings write, said once; the view sets it back to nil.
    var toast: UserMessage?
    /// The latest background "read" call; only tests wait for it (plan deviation N8).
    @ObservationIgnored private(set) var lastRead: Task<Void, Never>?

    private let service: any NotificationsService
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isLoadingPreferences = false
    /// The newest first-page request is in flight; a "Yana" waits for it.
    private(set) var isRefreshing = false

    init(service: any NotificationsService) {
        self.service = service
    }

    var hasMore: Bool {
        nextCursor != nil
    }

    /// Nothing left to show — not "this page was empty" (Android `isEmpty`).
    var isEmpty: Bool {
        phase == .ready && items.isEmpty && nextCursor == nil
    }

    /// What the card shows: the choice in flight, else what the server stored.
    var offlineAfterMinutes: Int? {
        pendingOfflineMinutes ?? preferences?.deviceOfflineAfterMinutes
    }

    /// Every time the screen shows: the first page again, the settings until read once.
    func appear() async {
        await load()
        await loadPreferencesIfNeeded()
    }

    /// The first page of the current filter; a list on screen stays while it asks.
    func load() async {
        generation += 1
        let mine = generation
        if phase != .ready { phase = .loading }
        isRefreshing = true
        do {
            let page = try await service.page(filter: filter, cursor: nil)
            guard mine == generation else { return }
            isRefreshing = false
            items = page.items
            nextCursor = page.nextCursor
            phase = .ready
            isOffline = false
            inlineMessage = nil
        } catch is CancellationError {
            if mine == generation { isRefreshing = false }
            return
        } catch {
            guard mine == generation else { return }
            isRefreshing = false
            let message = UserMessage(error)
            if phase != .ready {
                phase = .failed(message)
            } else if message == .noConnection || message == .timeout {
                isOffline = true
            } else {
                inlineMessage = message
            }
        }
    }

    /// The other filter from its first page; the old rows go at once (plan deviation N5).
    func setFilter(_ newFilter: NotificationFilter) async {
        guard newFilter != filter else { return }
        filter = newFilter
        items = []
        nextCursor = nil
        phase = .loading
        isOffline = false
        inlineMessage = nil
        await load()
    }

    /// One "Yana" at a time; a row already shown is not added twice.
    func loadMore() async {
        guard let cursor = nextCursor, phase == .ready, !isLoadingMore, !isRefreshing else { return }
        isLoadingMore = true
        inlineMessage = nil
        let mine = generation
        do {
            let page = try await service.page(filter: filter, cursor: cursor)
            guard mine == generation, nextCursor == cursor else {
                isLoadingMore = false
                return
            }
            let shown = Set(items.map(\.id))
            items += page.items.filter { !shown.contains($0.id) }
            nextCursor = page.nextCursor
            isOffline = false
        } catch is CancellationError {
            // Falls through: the single in-flight guard is released below.
        } catch {
            guard mine == generation, nextCursor == cursor else {
                isLoadingMore = false
                return
            }
            inlineMessage = UserMessage(error)
        }
        isLoadingMore = false
    }

    /// Read here, whether or not the row leads anywhere; the server is told
    /// behind it and its failure is silent (the row is unread again on the
    /// next fetch, which is the right way round for something this small).
    func open(_ notification: ParentNotification) -> SignedInView.HomeStep? {
        if !notification.isRead {
            let readAt = Date()
            items = items.map { $0.id == notification.id ? $0.markedRead(at: readAt) : $0 }
            let service = service
            let id = notification.id
            lastRead = Task {
                _ = try? await service.markRead(id)
            }
        }
        return NotificationLink.step(for: notification)
    }

    /// Read once; a failure is silent and asked again on the next visit.
    func loadPreferencesIfNeeded() async {
        guard preferences == nil, !isLoadingPreferences else { return }
        isLoadingPreferences = true
        defer { isLoadingPreferences = false }
        guard let fresh = try? await service.preferences() else { return }
        if preferences == nil {
            preferences = fresh
        }
    }

    /// Everything else sent back as read (a full replace). A refusal is a toast
    /// and the card goes back to the stored value.
    func setOfflineAfter(minutes: Int) async {
        guard let current = preferences, pendingOfflineMinutes == nil,
              current.deviceOfflineAfterMinutes != minutes else { return }
        pendingOfflineMinutes = minutes
        defer { pendingOfflineMinutes = nil }
        do {
            preferences = try await service.savePreferences(current.withDeviceOfflineAfter(minutes: minutes))
        } catch is CancellationError {
            return
        } catch {
            toast = UserMessage(error)
        }
    }
}
