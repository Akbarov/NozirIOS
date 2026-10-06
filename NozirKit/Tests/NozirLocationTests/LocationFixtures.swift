import Foundation
import NozirLocation
import NozirNetworking
import NozirTestSupport

/// A bearer that never expires: these tests are about the location calls, not tokens.
struct FixedToken: AccessTokenProvider {
    func validAccessToken() async throws -> String { "acc" }
    func refreshAfterRejection(of token: String) async throws -> String { "acc" }
    func endSession(rejecting token: String) async {}
}

func locationApi(_ replies: [FakeTransport.Reply]) -> (LocationApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: transport,
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5"),
        tokens: FixedToken()
    )
    return (LocationApi(client: client), transport)
}

let aliId = UUID(uuidString: "0B0E2A52-6A2F-4D8B-9A55-6F1B2A0C1D01")!
let zoneId = UUID(uuidString: "7C1D2E3F-4A5B-4C6D-8E7F-9A0B1C2D3E4F")!
let sosId = UUID(uuidString: "5D0C7E11-2B44-4C1A-8F0E-3A9B6C2D7E10")!
let childPath = "/v1/parent/children/0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01"

func instant(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

/// `LocationSnapshotDto` with a fix (`non_null`: absent, not null).
let fixJSON = """
{"occurredAt":"2026-10-06T07:10:00Z","latitude":41.3111,"longitude":69.2797,"accuracyMeters":24.6,\
"zoneId":"7c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f","zoneName":"Maktab","batteryPercent":64,"isStale":false}
"""

/// Only a reason: the phone answered, but had no position to give.
let reasonOnlyJSON = """
{"isStale":true,"unavailableReason":"LOCATION_OFF","unavailableAt":"2026-10-06T07:12:00Z"}
"""

func zoneJSON(active: String = #","isActive":false"#) -> String {
    """
    {"zoneId":"7c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f","childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01",\
    "name":"Maktab","latitude":41.3111,"longitude":69.2797,"radiusMeters":200,"notifyOnEnter":true,\
    "notifyOnExit":false,"createdAt":"2026-10-01T09:00:00Z"\(active)}
    """
}

func sosJSON(status: String = "ACTIVE", acknowledged: String = "") -> String {
    """
    {"id":"5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10","childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01",\
    "childName":"Ali","childPhoneE164":"+998901234567","triggeredAt":"2026-10-06T07:00:00Z",\
    "trigger":"BUTTON_HOLD","status":"\(status)","batteryPercent":31,"deviceOnline":true,\
    "latitude":41.3111,"longitude":69.2797,"accuracyMeters":12.0,"locationFixAt":"2026-10-06T06:59:30Z"\(acknowledged)}
    """
}

extension URLRequest {
    /// The body as a JSON object with any value types.
    var bodyObject: [String: Any]? {
        guard let httpBody else { return nil }
        return (try? JSONSerialization.jsonObject(with: httpBody)) as? [String: Any]
    }
}
