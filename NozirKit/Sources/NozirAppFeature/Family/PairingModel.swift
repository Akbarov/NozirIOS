import Foundation
import Observation
import NozirFamily

/// P04 (Android `PairingViewModel`), with the gap Android has closed: the server
/// stops returning a code once it is redeemed, so a code that disappears is
/// checked against the child before it is called expired.
@MainActor
@Observable
public final class PairingModel {
    public enum Phase: Equatable, Sendable {
        case loading
        case noCode
        case waiting(PairingCode)
        case paired
    }

    public private(set) var child: Child
    public private(set) var phase: Phase = .loading
    /// The phone a new code would retire; read only for a child already paired.
    public private(set) var connectedDevice: ChildDevice?
    public private(set) var isConfirmingReplacement = false
    public private(set) var isBusy = false
    public private(set) var message: UserMessage?

    private let family: FamilyStore
    private let pollInterval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var hasLooked = false

    public init(
        child: Child,
        family: FamilyStore,
        pollInterval: Duration = .seconds(4),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.child = child
        self.family = family
        self.pollInterval = pollInterval
        self.sleep = sleep
    }

    public var isAppInstalled: Bool {
        switch phase {
        case .waiting(let code): code.state == .appInstalled
        case .paired: true
        case .loading, .noCode: false
        }
    }

    /// Runs while the screen is visible and the app is active; cancelling the
    /// task that runs it (the screen went away, the app left the foreground)
    /// stops it. Only a code that is waiting is asked about.
    public func run() async {
        if hasLooked {
            await refresh()
        } else {
            hasLooked = true
            await firstLook()
        }
        while phase != .paired {
            do {
                try await sleep(pollInterval)
            } catch {
                return
            }
            await refresh()
        }
    }

    /// The "issue a code" button. A child who already has a phone is asked
    /// about first: redeeming a new code retires that phone.
    public func requestNewCode() async {
        guard !isBusy else { return }
        if connectedDevice != nil {
            isConfirmingReplacement = true
            message = nil
            return
        }
        await issue()
    }

    public func confirmReplacement() async {
        isConfirmingReplacement = false
        await issue()
    }

    public func dismissReplacement() {
        isConfirmingReplacement = false
    }

    private func firstLook() async {
        if child.pairingState == .paired {
            connectedDevice = try? await family.service.devices(of: child.id).first
        }
        do {
            if let code = try await family.service.currentPairingCode(for: child.id) {
                await show(code)
            } else if child.pairingState == .paired {
                phase = .noCode
            } else {
                await issue()
            }
        } catch is CancellationError {
            hasLooked = false
        } catch {
            phase = .noCode
            message = UserMessage(error)
        }
    }

    private func refresh() async {
        guard case .waiting = phase else { return }
        do {
            if let code = try await family.service.currentPairingCode(for: child.id) {
                await show(code)
                return
            }
            // The live code is gone: redeemed, or ran out. The child says which.
            let fresh = try await family.service.child(child.id)
            child = fresh
            family.replace(fresh)
            message = nil
            phase = fresh.pairingState == .paired ? .paired : .noCode
        } catch is CancellationError {
            return
        } catch {
            message = UserMessage(error)
        }
    }

    private func show(_ code: PairingCode) async {
        message = nil
        guard code.state == .paired else {
            phase = .waiting(code)
            return
        }
        phase = .paired
        if let fresh = try? await family.service.child(child.id) {
            child = fresh
            family.replace(fresh)
        }
    }

    private func issue() async {
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            phase = .waiting(try await family.service.issuePairingCode(for: child.id))
        } catch is CancellationError {
            return
        } catch {
            message = UserMessage(error)
            if phase == .loading { phase = .noCode }
        }
    }
}
