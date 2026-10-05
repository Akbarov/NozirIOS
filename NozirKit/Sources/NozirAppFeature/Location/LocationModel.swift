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
    /// True once a load for the shown child has finished, zones included.
    private(set) var isSettled = false

    private let location: any LocationService
    private let pause: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var shownChildId: UUID?
    /// Bumped when the child changes: an answer for the previous child is dropped.
    @ObservationIgnored private var generation = 0
    /// The wait in progress, owned here so leaving the screen can cancel it.
    @ObservationIgnored private var poll: Task<Void, Never>?
    /// Bumped on every start and cancel: a wait that was cancelled never writes.
    @ObservationIgnored private var requestToken = 0

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

    /// Where the camera belongs: the pin, else (once loading has finished) the
    /// first zone, else Tashkent. `nil` while the answer is not in yet, so a child
    /// switch never flashes Tashkent.
    var cameraTarget: Coordinate? {
        if let pin = snapshot?.coordinate { return pin }
        guard isSettled else { return nil }
        return zones.first?.coordinate ?? Self.fallbackCentre
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
            if let current = snapshot, Self.isNewer(current, than: fresh), !Self.isNewer(fresh, than: current) {
                // An overlapping load answered with an older fix: keep the newer one.
                phase = .ready
                isOffline = false
                inlineMessage = nil
            } else {
                show(fresh)
            }
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
                inlineMessage = nil
            } else {
                isOffline = false
                inlineMessage = message
            }
        }
        await reloadZones(of: id, generation: mine)
        if mine == generation { isSettled = true }
    }

    /// Zones and the tracking rule. Either failing is quiet: they keep what they had.
    func reloadZones() async {
        guard let id = childId else { return }
        await reloadZones(of: id, generation: generation)
    }

    private func reloadZones(of id: UUID, generation mine: Int) async {
        // Zones are read on a lapsed plan too: deleting is never restricted.
        if let fresh = try? await location.safeZones(of: id), mine == generation, id == childId {
            zones = fresh
        }
        // The tracking row is not shown while locked, so its rule is not read.
        guard phase != .locked else { return }
        if let rules = try? await family.service.rules(of: id), mine == generation, id == childId {
            tracking = rules.locationTracking
        }
    }

    /// Starts the wait on a task the model owns, so it can be cancelled when the
    /// screen goes away. Does nothing while a wait is already running.
    func startRequest() {
        guard let id = beginRequest() else { return }
        let token = requestToken
        poll = Task { [weak self] in
            await self?.runRequest(of: id, token: token)
        }
    }

    /// The screen closed or went to the background: stop waiting, stop asking.
    func cancelRequest() {
        requestToken += 1
        poll?.cancel()
        poll = nil
        // A "phone unreachable" or "try again in 30 s" is about that moment only.
        request = .idle
    }

    /// "Where are they now": wake the phone, then look again until something
    /// newer arrives or twelve looks have passed. Nothing newer is not an error.
    func requestFix() async {
        guard let id = beginRequest() else { return }
        await runRequest(of: id, token: requestToken)
    }

    private func beginRequest() -> UUID? {
        guard request != .waiting, phase != .locked, let id = childId else { return nil }
        requestToken += 1
        request = .waiting
        return id
    }

    private func runRequest(of id: UUID, token: Int) async {
        let mine = generation
        let before = snapshot
        func current() -> Bool { mine == generation && token == requestToken && !Task.isCancelled }
        do {
            let asked = try await location.requestLocation(of: id)
            guard current() else { return }
            guard asked else {
                request = .unreachable
                return
            }
            for _ in 0..<Self.pollAttempts {
                try await pause(Self.pollInterval)
                guard current() else { return }
                guard let fresh = try? await location.location(of: id) else { continue }
                guard current() else { return }
                if phase == .locked {
                    request = .idle
                    return
                }
                if Self.isNewer(fresh, than: before) {
                    show(fresh)
                    request = .idle
                    return
                }
            }
            request = .idle
        } catch is CancellationError {
            if mine == generation, token == requestToken { request = .idle }
        } catch let failure as ApiFailure where failure.code == .subscriptionRequired {
            if current() {
                phase = .locked
                request = .idle
            }
        } catch {
            if current() { request = .failed(UserMessage(error)) }
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
        requestToken += 1
        poll?.cancel()
        poll = nil
        request = .idle
        isSettled = false
        phase = .loading
    }
}
