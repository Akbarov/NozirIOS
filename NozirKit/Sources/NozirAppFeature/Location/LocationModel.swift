import Foundation
import Observation
import NozirDesignSystem
import NozirFamily
import NozirL10n
import NozirLocation
import NozirNetworking

/// P13. Where the chosen child's phone last was, the child's zones and the
/// tracking rule — asked again every time the tab is shown, never cached: the
/// one thing this app must never be confidently wrong about is where a child is.
/// "Where are they now" wakes the phone and then looks again every 2.5 s, up to
/// twelve times (Android's numbers, not measured).
@MainActor
@Observable
final class LocationModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// 404: the phone has never said anything. An answer, not a fault.
        case neverReported
        /// 403 `SUBSCRIPTION_REQUIRED`.
        case locked
        case noChild
        case failed(UserMessage)
    }

    enum Request: Equatable {
        case idle
        case waiting
        /// The server had no way to wake the phone.
        case unreachable
        case failed(UserMessage)
    }

    static let pollAttempts = 12
    static let pollInterval: Duration = .milliseconds(2500)
    /// Tashkent, when there is neither a pin nor a zone.
    static let fallbackCentre = Coordinate(latitude: 41.311081, longitude: 69.240562)

    var selectedChildId: UUID?
    let family: FamilyStore
    private(set) var phase: Phase = .loading
    private(set) var snapshot: LocationSnapshot?
    private(set) var isOffline = false
    /// A failure other than the connection, shown above a pin that stays.
    private(set) var inlineMessage: UserMessage?
    private(set) var zones: [SafeZone] = []
    private(set) var tracking: LocationTracking?
    private(set) var request: Request = .idle

    private let location: any LocationService
    private let pause: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var shownChildId: UUID?
    /// Bumped when the child changes: an answer for the previous child is dropped.
    @ObservationIgnored private var generation = 0

    init(
        family: FamilyStore,
        location: any LocationService,
        pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.family = family
        self.location = location
        self.pause = pause
    }

    var childId: UUID? {
        if let selectedChildId, family.child(selectedChildId) != nil { return selectedChildId }
        return family.children.first?.id
    }

    var child: Child? {
        childId.flatMap(family.child)
    }

    var showsSwitcher: Bool {
        family.children.count > 1
    }

    func switcherChildren(_ l10n: L10n) -> [NozirSwitcherChild] {
        family.children.enumerated().map { position, child in
            NozirSwitcherChild(
                id: child.id,
                name: child.displayName,
                tone: .forKey(child.avatarKey, position: position),
                accessibilityLabel: l10n.contentDescriptionChildAvatar(child.displayName)
            )
        }
    }

    /// The pin, else the first zone, else Tashkent.
    var cameraCentre: Coordinate {
        snapshot?.coordinate ?? zones.first?.coordinate ?? Self.fallbackCentre
    }

    /// Every time the tab (or the chosen child) is shown.
    func load() async {
        if !family.hasLoaded {
            do {
                try await family.refresh()
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(UserMessage(error))
                return
            }
        }
        guard let id = childId else {
            startFresh(for: nil)
            phase = .noChild
            return
        }
        if id != shownChildId {
            startFresh(for: id)
        }
        let mine = generation
        do {
            let fresh = try await location.location(of: id)
            guard mine == generation else { return }
            show(fresh)
        } catch is CancellationError {
            return
        } catch let failure as ApiFailure where failure.isNotFound {
            guard mine == generation else { return }
            snapshot = nil
            phase = .neverReported
            isOffline = false
            inlineMessage = nil
        } catch let failure as ApiFailure where failure.code == .subscriptionRequired {
            guard mine == generation else { return }
            snapshot = nil
            phase = .locked
        } catch {
            guard mine == generation else { return }
            let message = UserMessage(error)
            if snapshot == nil {
                phase = .failed(message)
            } else if message == .noConnection || message == .timeout {
                isOffline = true
            } else {
                inlineMessage = message
            }
        }
        await reloadZones()
    }

    /// Zones and the tracking rule. Either failing is quiet: they keep what they had.
    func reloadZones() async {
        guard let id = childId, phase != .locked else { return }
        let mine = generation
        if let fresh = try? await location.safeZones(of: id), mine == generation {
            zones = fresh
        }
        if let rules = try? await family.service.rules(of: id), mine == generation {
            tracking = rules.locationTracking
        }
    }

    /// "Where are they now": wake the phone, then look again until something
    /// newer arrives or twelve looks have passed. Nothing newer is not an error.
    func requestFix() async {
        guard request != .waiting, phase != .locked, let id = childId else { return }
        let mine = generation
        let before = snapshot
        request = .waiting
        do {
            let asked = try await location.requestLocation(of: id)
            guard mine == generation else { return }
            guard asked else {
                request = .unreachable
                return
            }
            for _ in 0..<Self.pollAttempts {
                try await pause(Self.pollInterval)
                guard mine == generation else { return }
                guard let fresh = try? await location.location(of: id) else { continue }
                guard mine == generation else { return }
                if Self.isNewer(fresh, than: before) {
                    show(fresh)
                    request = .idle
                    return
                }
            }
            request = .idle
        } catch is CancellationError {
            if mine == generation { request = .idle }
        } catch {
            if mine == generation { request = .failed(UserMessage(error)) }
        }
    }

    /// A later fix, or a later "no position" reason. Each is compared with its
    /// own kind: the two times come from different clocks.
    nonisolated static func isNewer(_ fresh: LocationSnapshot, than old: LocationSnapshot?) -> Bool {
        if let at = fresh.occurredAt, at > (old?.occurredAt ?? .distantPast) { return true }
        if let at = fresh.unavailableAt, at > (old?.unavailableAt ?? .distantPast) { return true }
        return false
    }

    private func show(_ fresh: LocationSnapshot) {
        snapshot = fresh
        phase = .ready
        isOffline = false
        inlineMessage = nil
    }

    private func startFresh(for id: UUID?) {
        generation += 1
        shownChildId = id
        snapshot = nil
        zones = []
        tracking = nil
        isOffline = false
        inlineMessage = nil
        request = .idle
        phase = .loading
    }
}
