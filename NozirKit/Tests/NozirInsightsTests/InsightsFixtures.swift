import Foundation
import NozirInsights
import NozirNetworking
import NozirTestSupport

/// A bearer that never expires: these tests are about the insight calls, not tokens.
struct FixedToken: AccessTokenProvider {
    func validAccessToken() async throws -> String { "acc" }
    func refreshAfterRejection(of token: String) async throws -> String { "acc" }
    func endSession(rejecting token: String) async {}
}

func insightsApi(_ replies: [FakeTransport.Reply]) -> (InsightsApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: transport,
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5"),
        tokens: FixedToken()
    )
    return (InsightsApi(client: client), transport)
}

let aliId = UUID(uuidString: "0B0E2A52-6A2F-4D8B-9A55-6F1B2A0C1D01")!
let sosId = UUID(uuidString: "5D0C7E11-2B44-4C1A-8F0E-3A9B6C2D7E10")!
let summaryId = UUID(uuidString: "9A1B2C3D-4E5F-4A6B-8C7D-0E1F2A3B4C5D")!

func instant(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

extension URLRequest {
    /// The query string as a dictionary, for asserting what was asked.
    var queryParameters: [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }
}

/// `ParentHomeResponse` as the backend writes it (`non_null`: absent, not null).
let fullHomeJSON = """
{"date":"2026-10-05","children":[{"childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01","displayName":"Ali",\
"ageGroup":"STAR","avatarKey":"teal","usedMinutes":95,"limitMinutes":120,"statusLevel":"ATTENTION",\
"needsAttention":true,"summarySentence":"Bugun tinch kun.","placeLabel":"Maktab",\
"placeSince":"2026-10-05T03:10:00Z","deviceOnline":true,"lastSeenAt":"2026-10-05T07:02:11Z"}],\
"familySummary":"Hammasi joyida.","pendingExtraTimeRequests":[],"pendingChallengeApprovals":0,\
"protection":{"level":"HEALTHY","childrenNeedingAttention":[]},\
"activeSosId":"5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10",\
"activeSos":{"sosId":"5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10","childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01",\
"childName":"Ali","triggeredAt":"2026-10-05T07:00:00Z"}}
"""

/// The least the backend can send: no optional field, a status this app does not know.
let bareHomeJSON = """
{"date":"2026-10-05","children":[{"childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01","displayName":"Ali",\
"ageGroup":"STAR","usedMinutes":0,"limitMinutes":120,"statusLevel":"SOMETHING_NEW","needsAttention":false,\
"deviceOnline":false}],"pendingExtraTimeRequests":[],"pendingChallengeApprovals":0,\
"protection":{"level":"HEALTHY","childrenNeedingAttention":[]}}
"""

/// `InsightSummaryResponse`.
func summaryJSON(period: String = "DAILY", start: String = "2026-10-04", end: String = "2026-10-04", risk: String = "GOOD") -> String {
    """
    {"summaryId":"9a1b2c3d-4e5f-4a6b-8c7d-0e1f2a3b4c5d","childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01",\
    "period":"\(period)","periodStart":"\(start)","periodEnd":"\(end)",\
    "paragraphs":["Ali kuni tinch otdi.","Kechqurun video koproq."],"recommendation":"Birga sayr qiling.",\
    "conversationQuestion":"Bu hafta nima yoqdi?","riskLevel":"\(risk)","source":"AI",\
    "generatedAt":"2026-10-05T01:00:00Z","contentNotice":"insight.notice.no_messages_read"}
    """
}

let requestId = UUID(uuidString: "7C3E1A20-1B2C-4D3E-8F4A-5B6C7D8E9F01")!

func extraTimeApi(_ replies: [FakeTransport.Reply]) -> (ExtraTimeApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: transport,
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5"),
        tokens: FixedToken()
    )
    return (ExtraTimeApi(client: client), transport)
}

/// `ExtraTimeRequestDto` as the backend writes it (`non_null`: absent, not
/// null). `kind: nil` leaves the field out; `extra` is spliced in before the
/// closing brace and must start with a comma.
func extraTimeJSON(kind: String? = "EXTRA_MINUTES", status: String = "PENDING", requested: Int = 30, extra: String = "") -> String {
    let kindField = kind.map { #""kind":"\#($0)","# } ?? ""
    return """
    {"id":"7c3e1a20-1b2c-4d3e-8f4a-5b6c7d8e9f01","childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01",\
    "childName":"Ali",\(kindField)"requestedMinutes":\(requested),"reason":"Uy vazifasi tugadi",\
    "status":"\(status)","createdAt":"2026-10-07T14:05:00Z","requestsInLastSevenDays":2\(extra)}
    """
}

/// `ExtraTimeRequestPage` around the given items.
func page(_ items: String...) -> String {
    "{\"items\":[" + items.joined(separator: ",") + "]}"
}
