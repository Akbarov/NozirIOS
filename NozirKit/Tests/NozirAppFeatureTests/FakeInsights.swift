import Foundation
import NozirInsights
import NozirNetworking

let notFound = ApiFailure.server(status: 404, error: ApiError(code: .notFound))

func day(_ text: String) -> LocalDate {
    LocalDate(text)!
}

/// Answers home and daily from queues (an empty queue is a phone with no
/// connection); weekly, usage and apps from functions of their arguments, so a
/// test can answer per week or per range. Records every call in order.
actor FakeInsights: InsightsService {
    struct Script: Sendable {
        var home: [Result<ParentHome, ApiFailure>] = []
        var daily: [Result<InsightSummary, ApiFailure>] = []
        var weekly: @Sendable (UUID, LocalDate) throws -> InsightSummary = { _, _ in throw notFound }
        var usage: @Sendable (UUID, LocalDate, LocalDate) throws -> [DailyUsage] = { _, _, _ in throw offline }
        var apps: @Sendable (UUID, UsageRange) throws -> AppBreakdown = { _, _ in throw offline }
    }

    private var script: Script
    /// "home", "daily latest", "daily 2026-10-04", "weekly 2026-09-28",
    /// "usage 2026-09-28…2026-10-04", "apps TODAY".
    private(set) var calls: [String] = []
    /// The child each child call was about, in call order.
    private(set) var childIds: [UUID] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    func add(_ change: @Sendable (inout Script) -> Void) {
        change(&script)
    }

    func home() async throws -> ParentHome {
        calls.append("home")
        guard !script.home.isEmpty else { throw offline }
        return try script.home.removeFirst().get()
    }

    func dailySummary(of childId: UUID, on date: LocalDate?) async throws -> InsightSummary {
        calls.append("daily \(date?.text ?? "latest")")
        childIds.append(childId)
        guard !script.daily.isEmpty else { throw offline }
        return try script.daily.removeFirst().get()
    }

    func weeklySummary(of childId: UUID, weekStart: LocalDate) async throws -> InsightSummary {
        calls.append("weekly \(weekStart.text)")
        childIds.append(childId)
        return try script.weekly(childId, weekStart)
    }

    func dailyUsage(of childId: UUID, from: LocalDate, to: LocalDate) async throws -> [DailyUsage] {
        calls.append("usage \(from.text)…\(to.text)")
        childIds.append(childId)
        return try script.usage(childId, from, to)
    }

    func appUsage(of childId: UUID, range: UsageRange) async throws -> AppBreakdown {
        calls.append("apps \(range.rawValue)")
        childIds.append(childId)
        return try script.apps(childId, range)
    }
}

func homeCard(
    _ name: String = "Ali",
    id: UUID = UUID(),
    attention: Bool = false,
    online: Bool = true,
    place: String? = nil,
    since: Date? = nil,
    used: Int = 95,
    limit: Int = 120,
    summary: String? = nil,
    avatar: String? = "teal",
    level: StatusLevel = .good
) -> ChildHomeCard {
    ChildHomeCard(
        id: id,
        displayName: name,
        avatarKey: avatar,
        usedMinutes: used,
        limitMinutes: limit,
        statusLevel: level,
        needsAttention: attention,
        summarySentence: summary,
        placeLabel: place,
        placeSince: since,
        deviceOnline: online
    )
}

func parentHome(
    _ children: [ChildHomeCard],
    date: LocalDate = day("2026-10-05"),
    familySummary: String? = nil,
    sos: ActiveSos? = nil,
    requests: [ExtraTimeRequest] = []
) -> ParentHome {
    ParentHome(date: date, children: children, familySummary: familySummary, activeSos: sos, pendingExtraTimeRequests: requests)
}

func insight(
    childId: UUID,
    start: String,
    end: String,
    paragraphs: [String] = ["Tinch kun."],
    question: String? = nil,
    risk: StatusLevel = .good
) -> InsightSummary {
    InsightSummary(
        id: UUID(),
        childId: childId,
        periodStart: day(start),
        periodEnd: day(end),
        paragraphs: paragraphs,
        recommendation: "Birga sayr qiling.",
        conversationQuestion: question,
        riskLevel: risk
    )
}

/// 2026-10-07T14:05:00Z.
let askedAt = Date(timeIntervalSince1970: 1_791_381_900)

/// A child's ask as the pending list carries it.
func extraTimeAsk(
    id: UUID = UUID(),
    childId: UUID = UUID(),
    name: String? = "Ali",
    kind: ExtraTimeKind = .extraMinutes,
    requested: Int = 30,
    reason: String = "Uy vazifasi tugadi",
    status: ExtraTimeStatus = .pending,
    granted: Int? = nil,
    note: String? = nil,
    week: Int? = 2
) -> ExtraTimeRequest {
    ExtraTimeRequest(
        id: id,
        childId: childId,
        childName: name,
        kind: kind,
        nightOf: kind == .bedtimeDelay ? day("2026-10-07") : nil,
        requestedMinutes: requested,
        reason: reason,
        status: status,
        grantedMinutes: granted,
        decisionNote: note,
        createdAt: askedAt,
        requestsInLastSevenDays: week
    )
}
