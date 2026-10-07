import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirInsights

private let protectionPath = "/v1/parent/children/0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01/protection"

@Suite struct ProtectionApiTests {
    @Test func aStatusIsReadAsTheServerWritesIt() async throws {
        let body = protectionJSON(
            permissions: [
                permissionJSON("USAGE_ACCESS", "GRANTED"),
                permissionJSON("OEM_AUTOSTART", "DENIED", revoked: true, key: "oem.xiaomi.autostart"),
            ],
            extra: #","lastReportAt":"2026-10-07T08:00:00Z","instructionKey":"oem.xiaomi.battery""#
        )
        let (api, transport) = protectionApi([.ok(body)])

        let status = try await api.status(childId: aliId)

        #expect(status == ProtectionStatus(
            childId: aliId,
            level: .degraded,
            permissions: [
                ProtectionPermission(kind: .usageAccess, status: .granted),
                ProtectionPermission(kind: .oemAutostart, status: .denied, wasRevoked: true, instructionKey: "oem.xiaomi.autostart"),
            ],
            lastReportAt: instant("2026-10-07T08:00:00Z"),
            isStale: false,
            manufacturer: "xiaomi",
            instructionKey: "oem.xiaomi.battery"
        ))
        #expect(status.kindsToFix == [.oemAutostart])
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == protectionPath)
        #expect(request.queryParameters.isEmpty)
    }

    // Review Focus 1 (spec §3): nothing ever heard from the phone.
    @Test func aPhoneThatNeverReportedIsBrokenAndStale() async throws {
        // As the backend writes it: generic keys, none for NOTIFICATIONS / LOCATION.
        let keys: [PermissionKind: String] = [
            .usageAccess: "oem.generic.usage", .overlay: "oem.generic.overlay",
            .battery: "oem.generic.battery", .oemAutostart: "oem.generic.autostart",
        ]
        let all = PermissionKind.allCases.map { permissionJSON($0.rawValue, "DENIED", key: keys[$0]) }
        let (api, _) = protectionApi([.ok(protectionJSON(
            level: "BROKEN", permissions: all, isStale: true, manufacturer: "*",
            extra: #","instructionKey":"oem.generic.autostart""#
        ))])

        let status = try await api.status(childId: aliId)

        #expect(status.level == .broken)
        #expect(status.isStale)
        #expect(status.lastReportAt == nil)
        #expect(status.instructionKey == "oem.generic.autostart")
        #expect(status.manufacturer == "*")
        #expect(status.kindsToFix == PermissionKind.allCases)
        #expect(status.permissions.allSatisfy { !$0.wasRevoked })
        #expect(status.permissions.map(\.instructionKey) == [
            "oem.generic.usage", "oem.generic.overlay", nil, nil, "oem.generic.battery", "oem.generic.autostart",
        ])
    }

    // Review Focus 2: a newer child app or server never invents a fault here.
    @Test func anUnknownKindOrStatusIsLeftOut() async throws {
        let permissions = [
            permissionJSON("CAMERA", "DENIED"),
            permissionJSON("USAGE_ACCESS", "PAUSED"),
            permissionJSON("OVERLAY", "SKIPPED"),
        ]
        let (api, _) = protectionApi([.ok(protectionJSON(level: "SOMETHING_NEW", permissions: permissions))])

        let status = try await api.status(childId: aliId)

        #expect(status.permissions == [ProtectionPermission(kind: .overlay, status: .skipped)])
    }

    // Final fix 1: "unknown = healthy" is only a floor; a fault in the same payload shows.
    @Test func anUnknownLevelWithNothingWrongIsHealthy() async throws {
        let granted = [permissionJSON("OVERLAY", "GRANTED")]
        let (api, _) = protectionApi([.ok(protectionJSON(level: "SOMETHING_NEW", permissions: granted))])

        #expect(try await api.status(childId: aliId).level == .healthy)
    }

    @Test func anUnknownLevelWithAFaultOrAStalePhoneIsDegraded() async throws {
        let denied = [permissionJSON("OVERLAY", "DENIED")]
        let granted = [permissionJSON("OVERLAY", "GRANTED")]
        let (api, _) = protectionApi([
            .ok(protectionJSON(level: "SOMETHING_NEW", permissions: denied)),
            .ok(protectionJSON(level: "SOMETHING_NEW", permissions: granted, isStale: true)),
            .ok(protectionJSON(level: "BROKEN", permissions: granted)),
        ])

        #expect(try await api.status(childId: aliId).level == .degraded)
        #expect(try await api.status(childId: aliId).level == .degraded)
        #expect(try await api.status(childId: aliId).level == .broken)
    }

    // Spec §4.1: optional fields are read defensively.
    @Test func absentOrUnreadableFieldsHaveSafeDefaults() async throws {
        let body = #"{"childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01","level":"HEALTHY","lastReportAt":"yesterday","permissions":[{"kind":"BATTERY","status":"GRANTED"}]}"#
        let (api, _) = protectionApi([.ok(body)])

        let status = try await api.status(childId: aliId)

        #expect(status.level == .healthy)
        #expect(status.permissions == [ProtectionPermission(kind: .battery, status: .granted)])
        #expect(status.lastReportAt == nil)
        #expect(!status.isStale)
        #expect(status.manufacturer == "")
        #expect(status.instructionKey == nil)
        #expect(status.kindsToFix.isEmpty)
    }

    @Test func oneGarbledPermissionDropsOnlyItself() async throws {
        let body = protectionJSON(permissions: [
            #"{"kind":5,"status":"DENIED"}"#,
            "7",
            permissionJSON("OVERLAY", "DENIED"),
            #"{"kind":"LOCATION","status":"DENIED","wasRevoked":"yes"}"#,
        ])
        let (api, _) = protectionApi([.ok(body)])

        let status = try await api.status(childId: aliId)

        #expect(status.permissions == [
            ProtectionPermission(kind: .overlay, status: .denied),
            ProtectionPermission(kind: .location, status: .denied),
        ])
    }

    @Test func aStatusWithoutALevelIsADecodingFailure() async {
        for body in [
            #"{"childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01"}"#,
            #"{"childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01","level":null}"#,
        ] {
            await expectDecodingFailure(body)
        }
    }

    @Test func aStatusWithoutAReadableChildIdIsADecodingFailure() async {
        await expectDecodingFailure(#"{"level":"HEALTHY"}"#)
        await expectDecodingFailure(#"{"childId":"not-a-uuid","level":"HEALTHY"}"#)
    }

    private func expectDecodingFailure(_ body: String) async {
        let (api, _) = protectionApi([.ok(body)])
        do {
            _ = try await api.status(childId: aliId)
            Issue.record("expected a decoding failure for \(body)")
        } catch ApiFailure.decoding {
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func aChildThatIsGoneIsNotFound() async {
        let (api, _) = protectionApi([.error(404, code: "NOT_FOUND")])

        do {
            _ = try await api.status(childId: aliId)
            Issue.record("expected not found")
        } catch let failure as ApiFailure {
            #expect(failure.isNotFound)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func instructionsAreSentForTheKindsAsked() async throws {
        let (api, transport) = protectionApi([.init(status: 202)])

        try await api.sendInstructions(childId: aliId, kinds: [.oemAutostart, .battery])

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == protectionPath + "/send-instructions")
        let body = try #require(request.jsonObject)
        #expect(body["kinds"] as? [String] == ["OEM_AUTOSTART", "BATTERY"])
        #expect(body.count == 1)
    }

    // Global Constraints: one tap, one POST.
    @Test func aRefusedSendIsThrownAndNotRetried() async {
        let (api, transport) = protectionApi([.error(500, code: "INTERNAL_ERROR"), .init(status: 202)])

        do {
            try await api.sendInstructions(childId: aliId, kinds: [.overlay])
            Issue.record("expected a failure")
        } catch {
            #expect(error is ApiFailure)
        }
        #expect(await transport.requests.count == 1)
    }
}
