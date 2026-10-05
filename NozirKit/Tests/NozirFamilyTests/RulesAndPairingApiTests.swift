import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirFamily

/// `RuleSnapshotResponse` with the parts 2a does not read left in, as the server sends them.
private func snapshotJSON(version: Int = 7, start: String = "22:00") -> String {
    """
    {"childId":"\(aliId.uuidString.lowercased())","version":\(version),\
    "screenTime":{"schoolDayMinutes":120,"weekendMinutes":180,"maxDailyBonusMinutes":60},\
    "maxTrustBonusMinutes":30,"locationTracking":{"isEnabled":false},\
    "bedtime":{"startTime":"\(start)","endTime":"07:00","windDownMinutes":30,"activeDays":[1,2,3,4,5,6,7]},\
    "appPolicies":[],"familyRules":[],"neverBlockedPackages":["com.android.dialer"]}
    """
}

private let codeJSON = """
    {"code":"472918","expiresAt":"2026-10-05T10:10:00Z","qrPayload":"nozir://pair?code=472918","state":"APP_INSTALLED"}
    """

private var rulesPath: String { FamilyApi.childPath(aliId) + "/rules" }

@Suite struct RulesAndPairingApiTests {
    @Test func rulesReadTheVersionAndBothRuleSets() async throws {
        let (api, transport) = familyApi([.ok(snapshotJSON())])

        let snapshot = try await api.rules(of: aliId)

        #expect(snapshot.version == 7)
        #expect(snapshot.screenTime == ScreenTimeLimit(schoolDayMinutes: 120, weekendMinutes: 180, maxDailyBonusMinutes: 60))
        #expect(snapshot.bedtime.start == ClockTime(hour: 22, minute: 0))
        #expect(snapshot.bedtime.activeDays == [1, 2, 3, 4, 5, 6, 7])
        #expect(await transport.requests.first?.url?.path == rulesPath)
    }

    @Test func aScreenTimeWriteNamesTheVersionItWasMadeAgainst() async throws {
        let (api, transport) = familyApi([.ok(snapshotJSON(version: 8))])

        let after = try await api.setScreenTime(
            ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 150, maxDailyBonusMinutes: 60),
            of: aliId,
            version: 7
        )

        #expect(after.version == 8)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == rulesPath + "/screen-time")
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"7\"")
        #expect(request.jsonObject?["schoolDayMinutes"] as? Int == 90)
    }

    @Test func aBedtimeWriteSendsWallClockTimes() async throws {
        let (api, transport) = familyApi([.ok(snapshotJSON(version: 9, start: "21:30"))])
        let bedtime = BedtimeSchedule(
            start: ClockTime(hour: 21, minute: 30),
            end: ClockTime(hour: 7, minute: 0),
            windDownMinutes: 30,
            activeDays: [1, 2, 3, 4, 5]
        )

        _ = try await api.setBedtime(bedtime, of: aliId, version: 8)

        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == rulesPath + "/bedtime")
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"8\"")
        let body = try #require(request.jsonObject)
        #expect(body["startTime"] as? String == "21:30")
        #expect(body["endTime"] as? String == "07:00")
        #expect(body["activeDays"] as? [Int] == [1, 2, 3, 4, 5])
    }

    @Test func theNightWindowCrossesMidnight() {
        let bedtime = BedtimeSchedule(start: ClockTime(hour: 22, minute: 0), end: ClockTime(hour: 7, minute: 0), windDownMinutes: 0, activeDays: [1])
        #expect(bedtime.lengthMinutes == 540)
        #expect(ClockTime("7:5") == ClockTime(hour: 7, minute: 5))
        #expect(ClockTime("24:00") == nil)
        #expect(ClockTime(hour: 7, minute: 5).text == "07:05")
    }

    @Test func aConflictIsTheServersAnswer() async {
        let (api, _) = familyApi([.error(409, code: "CONFLICT")])

        do {
            _ = try await api.setScreenTime(ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 90, maxDailyBonusMinutes: 60), of: aliId, version: 7)
            Issue.record("expected a conflict")
        } catch let failure as ApiFailure {
            #expect(failure.code == .conflict)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func noLiveCodeIsAnAnswerNotAFault() async throws {
        let (api, _) = familyApi([.error(404, code: "NOT_FOUND")])

        #expect(try await api.currentPairingCode(for: aliId) == nil)
    }

    @Test func aLiveCodeIsRead() async throws {
        let (api, transport) = familyApi([.ok(codeJSON)])

        let code = try #require(try await api.currentPairingCode(for: aliId))

        #expect(code.code == "472918")
        #expect(code.state == .appInstalled)
        #expect(code.qrContent == "nozir://pair?code=472918")
        #expect(await transport.requests.first?.url?.path == FamilyApi.childPath(aliId) + "/pairing-code")
    }

    @Test func aCodeWithoutAPayloadPutsTheCodeInTheQR() async throws {
        let (api, _) = familyApi([.ok(#"{"code":"472918","expiresAt":"2026-10-05T10:10:00Z","state":"CODE_ISSUED"}"#)])

        let code = try #require(try await api.currentPairingCode(for: aliId))

        #expect(code.qrContent == "472918")
    }

    @Test func issuingPostsWithoutABody() async throws {
        let (api, transport) = familyApi([.init(status: 201, body: codeJSON)])

        _ = try await api.issuePairingCode(for: aliId)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody == nil)
    }

    @Test func devicesAreListed() async throws {
        let (api, _) = familyApi([.ok("""
            [{"deviceId":"7c9e6679-7425-40de-944b-e07fc1f90ae7","childId":"\(aliId.uuidString.lowercased())",\
            "manufacturer":"Xiaomi","model":"Redmi Note 12","osVersion":"14","appVersion":"1.0.0",\
            "pairedAt":"2026-10-01T08:00:00Z","lastSeenAt":null,"isOnline":true}]
            """)])

        let devices = try await api.devices(of: aliId)

        #expect(devices.first?.label == "Xiaomi Redmi Note 12")
        #expect(devices.first?.isOnline == true)
    }

    @Test func theSubscriptionSaysWhichChildIsActive() async throws {
        let other = UUID()
        let (api, transport) = familyApi([
            .ok(#"{"familyId":"\#(UUID().uuidString)","tier":"FREE","status":"ACTIVE","state":"FREE","planCode":null,"channel":null,"currentPeriodEnd":null,"trialEndsAt":null,"graceUntil":null,"autoRenew":false,"entitlements":[],"quotas":{"CHILDREN":1},"activeChildId":"\#(aliId.uuidString.lowercased())"}"#),
            .ok(#"{"activeChildId":null}"#),
        ])

        let free = try await api.subscription()
        #expect(free.isChildActive(aliId))
        #expect(!free.isChildActive(other))

        let entitled = try await api.chooseActiveChild(other)
        #expect(entitled.isChildActive(other))
        let request = try #require(await transport.requests.last)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/v1/parent/subscription/active-child")
        #expect(request.jsonBody?["childId"]?.lowercased() == other.uuidString.lowercased())
    }

    @Test func theParentsRecordAndLanguage() async throws {
        let parent = #"{"parentId":"\#(UUID().uuidString)","familyId":"\#(UUID().uuidString)","phoneE164":null,"displayName":"Zohid","locale":"uz","timeZone":"Asia/Tashkent","role":"OWNER","createdAt":"2026-10-01T08:00:00Z"}"#
        let (api, transport) = familyApi([.ok(parent), .ok(parent)])

        #expect(try await api.me().displayName == "Zohid")
        _ = try await api.updateLocale("ru")

        let request = try #require(await transport.requests.last)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/parent/me")
        #expect(request.jsonBody == ["locale": "ru"])
    }
}
