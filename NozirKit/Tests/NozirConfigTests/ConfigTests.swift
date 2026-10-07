import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirConfig

private let identity = ClientIdentity(appVersion: "1.0.0", osVersion: "17.5")

// ServerConfigResponse, ServerConfigDtos.kt — including fields the app ignores.
private func configBody(updateRequired: Bool) -> String {
    #"""
    {"minSupportedVersion":"1.0.0","latestVersion":"1.1.0","updateRequired":\#(updateRequired),"featureFlags":{"PHONE_OTP_SIGN_IN":false},"emergencyContacts":{"emergencyNumber":"112","policeNumber":"102","ambulanceNumber":"103","fireNumber":"101","childHelplineNumber":"1246","isChildHelplineEnabled":false},"usageSyncIntervalSeconds":900,"locationHeartbeatSeconds":300,"dataDeletionDelayDays":30,"privacyPolicyUrl":"https://nozir.syncoder.uz/privacy","termsUrl":"https://nozir.syncoder.uz/terms","supportUrl":"https://nozir.syncoder.uz/support"}
    """#
}

private func config(updateRequired: Bool) -> ServerConfig {
    ServerConfig(
        minSupportedVersion: "1.0.0",
        latestVersion: "1.1.0",
        updateRequired: updateRequired,
        featureFlags: ["PHONE_OTP_SIGN_IN": false],
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
        dataDeletionDelayDays: 30
    )
}

private func freshCache() -> UserDefaultsConfigCache {
    UserDefaultsConfigCache(defaults: UserDefaults(suiteName: "nozir.tests.\(UUID().uuidString)")!)
}

private func makeLoader(_ replies: [FakeTransport.Reply], cache: any ConfigCache, appVersion: String = "1.0.0")
    -> (ConfigLoader, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(baseURL: URL(string: "https://api.test")!, transport: transport, identity: identity)
    return (ConfigLoader(api: ConfigApi(client: client), cache: cache, appVersion: appVersion), transport)
}

@Suite struct ConfigLoaderTests {
    @Test func asksAsTheIOSParentAppWithoutABearer() async throws {
        let (loader, transport) = makeLoader([.ok(configBody(updateRequired: false))], cache: freshCache())

        let loaded = await loader.load()

        let requests = await transport.requests
        let sent = try #require(requests.first)
        #expect(loaded == config(updateRequired: false))
        #expect(sent.url?.absoluteString == "https://api.test/v1/config?clientKind=PARENT_IOS")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
        // A weak network must not hold the launch spinner for URLSession's 60 s default.
        #expect(sent.timeoutInterval == 8)
    }

    @Test func offlineFallsBackToTheLastConfigForThisVersion() async {
        let cache = freshCache()
        let (online, _) = makeLoader([.ok(configBody(updateRequired: true))], cache: cache)
        _ = await online.load()

        let (offline, _) = makeLoader([], cache: cache)
        #expect(await offline.load() == config(updateRequired: true))
    }

    // Review Focus 3: an "update required" remembered by the old version must
    // not lock out the version the parent just updated to.
    @Test func aCachedConfigFromAnotherAppVersionIsNotUsed() async {
        let cache = freshCache()
        let (old, _) = makeLoader([.ok(configBody(updateRequired: true))], cache: cache, appVersion: "1.0.0")
        _ = await old.load()

        let (updatedOffline, _) = makeLoader([], cache: cache, appVersion: "1.1.0")
        #expect(await updatedOffline.load() == nil)
    }

    @Test func offlineWithNothingCachedIsNil() async {
        let (loader, _) = makeLoader([], cache: freshCache())
        #expect(await loader.load() == nil)
    }

    @Test func aServerErrorFallsBackToTheCacheToo() async {
        let cache = freshCache()
        cache.save(config(updateRequired: false), appVersion: "1.0.0")
        let (loader, _) = makeLoader([.error(500, code: "INTERNAL_ERROR")], cache: cache)
        #expect(await loader.load() == config(updateRequired: false))
    }
}

@Suite struct UpdateGateTests {
    @Test func noConfigNeverBlocks() {
        #expect(!UpdateGate.blocks(nil))
    }

    @Test func aRequiredUpdateBlocks() {
        #expect(UpdateGate.blocks(config(updateRequired: true)))
    }

    @Test func aCurrentAppIsNotBlocked() {
        #expect(!UpdateGate.blocks(config(updateRequired: false)))
    }

    // SOS (P15) is never behind the wall.
    @Test func anExemptScreenIsNeverBlocked() {
        #expect(!UpdateGate.blocks(config(updateRequired: true), isExempt: true))
    }
}

@Suite struct ServerConfigDecodingTests {
    @Test func theDeletionWaitIsRead() throws {
        let decoded = try NozirJSON.decoder().decode(ServerConfig.self, from: Data(configBody(updateRequired: false).utf8))

        #expect(decoded.dataDeletionDelayDays == 30)
    }

    // An older server, or a config cached before this field existed.
    @Test func aConfigWithoutTheDeletionWaitHasNone() throws {
        let body = configBody(updateRequired: false).replacingOccurrences(of: #""dataDeletionDelayDays":30,"#, with: "")

        let decoded = try NozirJSON.decoder().decode(ServerConfig.self, from: Data(body.utf8))

        #expect(decoded.dataDeletionDelayDays == nil)
    }
}
