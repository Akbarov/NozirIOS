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
/// closing brace and must start with a comma. `childName: nil` leaves it out, as Home does.
func extraTimeJSON(kind: String? = "EXTRA_MINUTES", status: String = "PENDING", requested: Int = 30, childName: String? = "Ali", extra: String = "") -> String {
    let nameField = childName.map { #""childName":"\#($0)","# } ?? ""
    let kindField = kind.map { #""kind":"\#($0)","# } ?? ""
    return """
    {"id":"7c3e1a20-1b2c-4d3e-8f4a-5b6c7d8e9f01","childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01",\
    \(nameField)\(kindField)"requestedMinutes":\(requested),"reason":"Uy vazifasi tugadi",\
    "status":"\(status)","createdAt":"2026-10-07T14:05:00Z","requestsInLastSevenDays":2\(extra)}
    """
}

/// `ExtraTimeRequestPage` around the given items.
func page(_ items: String...) -> String {
    "{\"items\":[" + items.joined(separator: ",") + "]}"
}

func protectionApi(_ replies: [FakeTransport.Reply]) -> (ProtectionApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: transport,
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5"),
        tokens: FixedToken()
    )
    return (ProtectionApi(client: client), transport)
}

/// `PermissionStateDto` as the backend writes it: `instructionKey` is absent when null.
func permissionJSON(_ kind: String, _ status: String, revoked: Bool = false, key: String? = nil) -> String {
    let keyField = key.map { #","instructionKey":"\#($0)""# } ?? ""
    return #"{"kind":"\#(kind)","status":"\#(status)","wasRevoked":\#(revoked)\#(keyField)}"#
}

/// `ProtectionStatusResponse` for Ali (`non_null`: `lastReportAt` and
/// `instructionKey` are absent unless `extra` adds them; it must start with a comma).
func protectionJSON(
    level: String = "DEGRADED",
    permissions: [String] = [],
    isStale: Bool = false,
    manufacturer: String = "xiaomi",
    extra: String = ""
) -> String {
    let list = permissions.joined(separator: ",")
    return #"{"childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01","level":"\#(level)","permissions":[\#(list)],"isStale":\#(isStale),"manufacturer":"\#(manufacturer)"\#(extra)}"#
}

func notificationsApi(_ replies: [FakeTransport.Reply]) -> (NotificationsApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: transport,
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5"),
        tokens: FixedToken()
    )
    return (NotificationsApi(client: client), transport)
}

let notificationId = UUID(uuidString: "3F2A1B0C-9D8E-4F7A-8B6C-5D4E3F2A1B0C")!
let digestId = UUID(uuidString: "4A5B6C7D-8E9F-4A0B-9C1D-2E3F4A5B6C7D")!

/// `NotificationResponse` as the backend writes it (`non_null`: `childId`,
/// `childName`, `deepLink` and `readAt` are absent when null;
/// `localisationArgs` is always there). By default Ali's SOS. `args: nil` and
/// `occurredAt: nil` leave those fields out (a broken row); `extra` is spliced
/// in before the closing brace and must start with a comma.
func notificationJSON(
    id: String = "3f2a1b0c-9d8e-4f7a-8b6c-5d4e3f2a1b0c",
    type: String = "SOS_TRIGGERED",
    tier: String = "CRITICAL",
    key: String = "notification.sos.triggered",
    args: String? = "{}",
    child: Bool = true,
    deepLink: String? = "nozir://sos/5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10",
    occurredAt: String? = "2026-10-07T08:00:00Z",
    extra: String = ""
) -> String {
    let argsField = args.map { #","localisationArgs":\#($0)"# } ?? ""
    let childFields = child ? #","childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01","childName":"Ali""# : ""
    let linkField = deepLink.map { #","deepLink":"\#($0)""# } ?? ""
    let timeField = occurredAt.map { #","occurredAt":"\#($0)""# } ?? ""
    return #"{"id":"\#(id)","type":"\#(type)","tier":"\#(tier)","localisationKey":"\#(key)""#
        + argsField + childFields + linkField + timeField + extra + "}"
}

/// `NotificationPage`: `nextCursor` is absent on the last page.
func notificationPageJSON(_ items: [String], nextCursor: String? = nil) -> String {
    let cursorField = nextCursor.map { #","nextCursor":"\#($0)""# } ?? ""
    return #"{"items":["# + items.joined(separator: ",") + "]" + cursorField + "}"
}

/// `NotificationPreferencesResponse` with quiet hours set (`LocalTime.toString()`: "22:00").
let preferencesJSON = #"{"dailyPushCap":1,"quietHoursStart":"22:00","quietHoursEnd":"07:00","mutedTypes":["LIMIT_REACHED"],"smsForCriticalEnabled":true,"deviceOfflineAfterMinutes":360}"#
