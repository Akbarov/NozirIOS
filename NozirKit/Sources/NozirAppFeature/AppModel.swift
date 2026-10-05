import Foundation
import Observation
import NozirAuth
import NozirConfig

public enum AppPhase: Equatable, Sendable {
    case launching
    case updateRequired(emergencyNumber: String?)
    case signedOut
    case signedIn
}

/// Which of the app's top-level states is showing, and every move between them.
@MainActor
@Observable
public final class AppModel {
    public private(set) var phase: AppPhase = .launching

    /// From the server config; the SOS sheet offers to dial it. Nil until a
    /// config (fresh or cached) has been read.
    public private(set) var emergencyNumber: String?

    /// openapi: re-fetch the config after more than an hour in the background.
    private let configRefreshAfter: TimeInterval = 3_600
    private let config: any ConfigLoading
    private let tokens: any TokenStore
    private let sessionEnded: AsyncStream<Void>
    private let logout: @Sendable () async throws -> Void
    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private var sessionWatch: Task<Void, Never>?

    public init(
        config: any ConfigLoading,
        tokens: any TokenStore,
        sessionEnded: AsyncStream<Void>,
        logout: @escaping @Sendable () async throws -> Void
    ) {
        self.config = config
        self.tokens = tokens
        self.sessionEnded = sessionEnded
        self.logout = logout
    }

    /// Starts listening for the end of the session (once, for the life of the
    /// model — not of any view) and decides the first screen.
    public func start() async {
        if sessionWatch == nil {
            let events = sessionEnded
            sessionWatch = Task { [weak self] in
                for await _ in events {
                    self?.handleSessionEnded()
                }
            }
        }
        await evaluate()
    }

    public func didSignIn() {
        phase = .signedIn
    }

    /// Tells the server first, then forgets the session whether or not the
    /// server heard: a parent who pressed "sign out" is signed out.
    public func signOut() async {
        try? await logout()
        tokens.clear()
        phase = .signedOut
    }

    /// The refresher found the session revoked or expired. The update wall,
    /// if it is up, stays up.
    public func handleSessionEnded() {
        if phase == .signedIn {
            phase = .signedOut
        }
    }

    public func sceneDidEnterBackground(at date: Date) {
        backgroundedAt = date
    }

    public func sceneDidBecomeActive(at date: Date) async {
        guard let left = backgroundedAt else { return }
        backgroundedAt = nil
        guard date.timeIntervalSince(left) > configRefreshAfter else { return }
        await evaluate()
    }

    private func evaluate() async {
        let loaded = await config.load()
        emergencyNumber = loaded?.emergencyContacts.emergencyNumber
        if UpdateGate.blocks(loaded) {
            phase = .updateRequired(emergencyNumber: emergencyNumber)
            return
        }
        phase = tokens.load() == nil ? .signedOut : .signedIn
    }
}
