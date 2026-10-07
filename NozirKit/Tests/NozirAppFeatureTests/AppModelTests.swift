import Foundation
import Testing
import NozirAuth
import NozirConfig
@testable import NozirAppFeature

private func config(updateRequired: Bool, deletionDays: Int? = nil) -> ServerConfig {
    ServerConfig(
        minSupportedVersion: "1.0.0",
        latestVersion: "1.1.0",
        updateRequired: updateRequired,
        featureFlags: [:],
        emergencyContacts: EmergencyContacts(
            emergencyNumber: "112",
            policeNumber: "102",
            ambulanceNumber: "103",
            fireNumber: "101",
            childHelplineNumber: "1246",
            isChildHelplineEnabled: false
        ),
        privacyPolicyUrl: "https://nozir.syncoder.uz/privacy",
        termsUrl: "https://nozir.syncoder.uz/terms",
        supportUrl: "https://nozir.syncoder.uz/support",
        dataDeletionDelayDays: deletionDays
    )
}

private let someTokens = TokenPair(
    accessToken: "acc-1",
    accessTokenExpiresAt: Date(timeIntervalSince1970: 1_791_027_969),
    refreshToken: "ref-1",
    refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_793_619_069)
)

private actor FakeConfig: ConfigLoading {
    private var result: ServerConfig?
    private(set) var loads = 0

    init(_ result: ServerConfig?) {
        self.result = result
    }

    func set(_ result: ServerConfig?) {
        self.result = result
    }

    func load() async -> ServerConfig? {
        loads += 1
        return result
    }
}

private actor LogoutEndpoint {
    private(set) var calls = 0
    private let fails: Bool

    init(fails: Bool = false) {
        self.fails = fails
    }

    func logout() throws {
        calls += 1
        if fails { throw URLError(.notConnectedToInternet) }
    }
}

@MainActor
private func makeModel(
    config: FakeConfig,
    tokens: InMemoryTokenStore,
    logout: LogoutEndpoint = LogoutEndpoint()
) -> AppModel {
    AppModel(
        config: config,
        tokens: tokens,
        sessionEnded: AsyncStream { _ in },
        logout: { try await logout.logout() }
    )
}

@MainActor
@Suite struct AppModelTests {
    @Test func aRequiredUpdateShowsTheWallWithTheEmergencyNumber() async {
        let model = makeModel(config: FakeConfig(config(updateRequired: true)), tokens: InMemoryTokenStore(someTokens))
        await model.start()
        #expect(model.phase == .updateRequired(emergencyNumber: "112"))
    }

    @Test func noConfigAndNoSessionIsSignedOut() async {
        let model = makeModel(config: FakeConfig(nil), tokens: InMemoryTokenStore())
        await model.start()
        #expect(model.phase == .signedOut)
    }

    @Test func noConfigWithASessionIsSignedIn() async {
        let model = makeModel(config: FakeConfig(nil), tokens: InMemoryTokenStore(someTokens))
        await model.start()
        #expect(model.phase == .signedIn)
    }

    @Test func signingInMovesToSignedIn() async {
        let model = makeModel(config: FakeConfig(config(updateRequired: false)), tokens: InMemoryTokenStore())
        await model.start()
        model.didSignIn()
        #expect(model.phase == .signedIn)
    }

    @Test func signingOutTellsTheServerAndForgetsTheSession() async {
        let tokens = InMemoryTokenStore(someTokens)
        let logout = LogoutEndpoint()
        let model = makeModel(config: FakeConfig(nil), tokens: tokens, logout: logout)
        await model.start()

        await model.signOut()

        #expect(await logout.calls == 1)
        #expect(tokens.load() == nil)
        #expect(model.phase == .signedOut)
    }

    @Test func signingOutOfflineStillForgetsTheSession() async {
        let tokens = InMemoryTokenStore(someTokens)
        let model = makeModel(config: FakeConfig(nil), tokens: tokens, logout: LogoutEndpoint(fails: true))
        await model.start()

        await model.signOut()

        #expect(tokens.load() == nil)
        #expect(model.phase == .signedOut)
    }

    @Test func theServerEndingTheSessionSignsOut() async {
        let model = makeModel(config: FakeConfig(nil), tokens: InMemoryTokenStore(someTokens))
        await model.start()

        model.handleSessionEnded()

        #expect(model.phase == .signedOut)
    }

    // Review: the model, not a view's .task, listens for the end of the session,
    // so a rebuilt scene cannot leave it deaf.
    @Test func theServerEndingTheSessionIsNoticedWithoutAnyView() async {
        let (events, continuation) = AsyncStream<Void>.makeStream()
        let model = AppModel(
            config: FakeConfig(nil),
            tokens: InMemoryTokenStore(someTokens),
            sessionEnded: events,
            logout: {}
        )
        await model.start()

        continuation.yield()
        for _ in 0..<200 where model.phase != .signedOut { await Task.yield() }

        #expect(model.phase == .signedOut)
    }

    @Test func theSessionEndingDoesNotHideTheUpdateWall() async {
        let model = makeModel(config: FakeConfig(config(updateRequired: true)), tokens: InMemoryTokenStore(someTokens))
        await model.start()

        model.handleSessionEnded()

        #expect(model.phase == .updateRequired(emergencyNumber: "112"))
    }

    @Test func returningAfterMoreThanAnHourAsksTheServerAgain() async {
        let server = FakeConfig(config(updateRequired: false))
        let model = makeModel(config: server, tokens: InMemoryTokenStore(someTokens))
        await model.start()
        await server.set(config(updateRequired: true))
        let leftAt = Date(timeIntervalSince1970: 1_791_027_069)

        model.sceneDidEnterBackground(at: leftAt)
        await model.sceneDidBecomeActive(at: leftAt.addingTimeInterval(3_601))

        #expect(await server.loads == 2)
        #expect(model.phase == .updateRequired(emergencyNumber: "112"))
    }

    @Test func returningWithinTheHourDoesNotAskAgain() async {
        let server = FakeConfig(config(updateRequired: false))
        let model = makeModel(config: server, tokens: InMemoryTokenStore(someTokens))
        await model.start()
        let leftAt = Date(timeIntervalSince1970: 1_791_027_069)

        model.sceneDidEnterBackground(at: leftAt)
        await model.sceneDidBecomeActive(at: leftAt.addingTimeInterval(600))

        #expect(await server.loads == 1)
        #expect(model.phase == .signedIn)
    }

    @Test func theWallComesDownWhenTheServerNoLongerRequiresAnUpdate() async {
        let server = FakeConfig(config(updateRequired: true))
        let model = makeModel(config: server, tokens: InMemoryTokenStore(someTokens))
        await model.start()
        await server.set(config(updateRequired: false))
        let leftAt = Date(timeIntervalSince1970: 1_791_027_069)

        model.sceneDidEnterBackground(at: leftAt)
        await model.sceneDidBecomeActive(at: leftAt.addingTimeInterval(3_601))

        #expect(model.phase == .signedIn)
    }

    @Test func theEmergencyNumberIsKeptForSos() async {
        let model = makeModel(config: FakeConfig(config(updateRequired: false)), tokens: InMemoryTokenStore(someTokens))

        await model.start()

        #expect(model.phase == .signedIn)
        #expect(model.emergencyNumber == "112")
    }

    @Test func noConfigNoEmergencyNumber() async {
        let model = makeModel(config: FakeConfig(nil), tokens: InMemoryTokenStore(someTokens))

        await model.start()

        #expect(model.emergencyNumber == nil)
    }

    // P20: the server has already revoked every session; asking it to log out
    // again would only fail.
    @Test func signingOutLocallyForgetsTheSessionWithoutTheServer() async {
        let tokens = InMemoryTokenStore(someTokens)
        let logout = LogoutEndpoint()
        let model = makeModel(config: FakeConfig(nil), tokens: tokens, logout: logout)
        await model.start()

        model.signOutLocally()

        #expect(await logout.calls == 0)
        #expect(tokens.load() == nil)
        #expect(model.phase == .signedOut)
    }

    @Test func thePrivacyConfigComesWithTheServerConfig() async {
        let model = makeModel(config: FakeConfig(config(updateRequired: false, deletionDays: 7)), tokens: InMemoryTokenStore(someTokens))

        await model.start()

        #expect(model.privacyConfig == PrivacyConfig(
            deletionDelayDays: 7,
            policyURL: URL(string: "https://nozir.syncoder.uz/privacy")
        ))
    }

    @Test func noConfigNoPrivacyConfig() async {
        let model = makeModel(config: FakeConfig(nil), tokens: InMemoryTokenStore(someTokens))

        await model.start()

        #expect(model.privacyConfig == .absent)
    }
}
