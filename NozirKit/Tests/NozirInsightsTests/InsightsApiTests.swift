import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirInsights

private let childPath = "/v1/parent/children/0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01"

@Suite struct InsightsApiTests {
    @Test func homeReadsTheServersShape() async throws {
        let (api, transport) = insightsApi([.ok(fullHomeJSON)])

        let home = try await api.home()

        #expect(home.date == LocalDate("2026-10-05"))
        #expect(home.familySummary == "Hammasi joyida.")
        #expect(home.children == [ChildHomeCard(
            id: aliId,
            displayName: "Ali",
            avatarKey: "teal",
            usedMinutes: 95,
            limitMinutes: 120,
            statusLevel: .attention,
            needsAttention: true,
            summarySentence: "Bugun tinch kun.",
            placeLabel: "Maktab",
            placeSince: instant("2026-10-05T03:10:00Z"),
            deviceOnline: true,
            lastSeenAt: instant("2026-10-05T07:02:11Z")
        )])
        #expect(home.activeSos == ActiveSos(sosId: sosId, childId: aliId, childName: "Ali", triggeredAt: instant("2026-10-05T07:00:00Z")))
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/parent/home")
        #expect(request.queryParameters.isEmpty)
    }

    @Test func aHomeWithNothingOptionalStillLoads() async throws {
        let (api, _) = insightsApi([.ok(bareHomeJSON)])

        let home = try await api.home()

        let card = try #require(home.children.first)
        #expect(card.statusLevel == .good)
        #expect(card.avatarKey == nil)
        #expect(card.summarySentence == nil)
        #expect(card.placeLabel == nil)
        #expect(card.placeSince == nil)
        #expect(!card.deviceOnline)
        #expect(home.familySummary == nil)
        #expect(home.activeSos == nil)
    }

    @Test func theDailySummaryWithoutADayIsTheLatest() async throws {
        let (api, transport) = insightsApi([.ok(summaryJSON())])

        let summary = try await api.dailySummary(of: aliId, on: nil)

        #expect(summary == InsightSummary(
            id: summaryId,
            childId: aliId,
            periodStart: LocalDate("2026-10-04")!,
            periodEnd: LocalDate("2026-10-04")!,
            paragraphs: ["Ali kuni tinch otdi.", "Kechqurun video koproq."],
            recommendation: "Birga sayr qiling.",
            conversationQuestion: "Bu hafta nima yoqdi?",
            riskLevel: .good
        ))
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == childPath + "/summaries/daily")
        #expect(request.queryParameters.isEmpty)
    }

    @Test func aDayIsSentAsTheServerWritesIt() async throws {
        let (api, transport) = insightsApi([.ok(summaryJSON())])

        _ = try await api.dailySummary(of: aliId, on: LocalDate("2026-10-04"))

        let request = try #require(await transport.requests.first)
        #expect(request.queryParameters == ["date": "2026-10-04"])
    }

    @Test func aSummaryThatDoesNotExistIsNotFound() async {
        let (api, _) = insightsApi([.error(404, code: "NOT_FOUND")])

        do {
            _ = try await api.dailySummary(of: aliId, on: nil)
            Issue.record("expected not found")
        } catch let failure as ApiFailure {
            #expect(failure.isNotFound)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func theWeeklySummaryIsAskedForByItsMonday() async throws {
        let (api, transport) = insightsApi([.ok(summaryJSON(period: "WEEKLY", start: "2026-09-28", end: "2026-10-04", risk: "ACTION"))])

        let summary = try await api.weeklySummary(of: aliId, weekStart: LocalDate("2026-09-28")!)

        #expect(summary.riskLevel == .action)
        #expect(summary.periodEnd == LocalDate("2026-10-04"))
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == childPath + "/summaries/weekly")
        #expect(request.queryParameters == ["weekStart": "2026-09-28"])
    }

    @Test func dailyUsageSendsBothEnds() async throws {
        let body = #"[{"date":"2026-09-28","usedMinutes":130,"limitMinutes":120},{"date":"2026-09-29","usedMinutes":0,"limitMinutes":120}]"#
        let (api, transport) = insightsApi([.ok(body)])

        let days = try await api.dailyUsage(of: aliId, from: LocalDate("2026-09-28")!, to: LocalDate("2026-10-04")!)

        #expect(days == [
            DailyUsage(date: LocalDate("2026-09-28")!, usedMinutes: 130, limitMinutes: 120),
            DailyUsage(date: LocalDate("2026-09-29")!, usedMinutes: 0, limitMinutes: 120),
        ])
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == childPath + "/usage/daily")
        #expect(request.queryParameters == ["from": "2026-09-28", "to": "2026-10-04"])
    }

    @Test(arguments: [(UsageRange.today, "TODAY"), (.lastSevenDays, "LAST_7_DAYS"), (.lastThirtyDays, "LAST_30_DAYS")])
    func appUsageSendsTheRange(range: UsageRange, raw: String) async throws {
        let body = #"{"range":"\#(raw)","totalMinutes":0,"entries":[]}"#
        let (api, transport) = insightsApi([.ok(body)])

        let breakdown = try await api.appUsage(of: aliId, range: range)

        #expect(breakdown == AppBreakdown(range: range, totalMinutes: 0, entries: []))
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == childPath + "/usage/apps")
        #expect(request.queryParameters == ["range": raw])
    }

    @Test func appEntriesAreReadAsSentAndUnknownRangesAreToday() async throws {
        let body = """
        {"range":"LAST_YEAR","totalMinutes":75,"entries":[\
        {"packageId":"com.google.android.youtube","displayName":"YouTube","minutes":50},\
        {"packageId":"nozir.other_apps","minutes":25}]}
        """
        let (api, _) = insightsApi([.ok(body)])

        let breakdown = try await api.appUsage(of: aliId, range: .today)

        #expect(breakdown.range == .today)
        #expect(breakdown.totalMinutes == 75)
        #expect(breakdown.entries == [
            AppUsageEntry(packageId: "com.google.android.youtube", displayName: "YouTube", minutes: 50),
            AppUsageEntry(packageId: "nozir.other_apps", displayName: "", minutes: 25),
        ])
        #expect(!breakdown.entries[0].isOtherApps)
        #expect(breakdown.entries[1].isOtherApps)
    }

    // P17: the waiting asks come with home.
    @Test func homeCarriesTheWaitingAsks() async throws {
        let body = bareHomeJSON.replacingOccurrences(
            of: #""pendingExtraTimeRequests":[]"#,
            with: #""pendingExtraTimeRequests":["# + extraTimeJSON(childName: nil) + "]"
        )
        let (api, _) = insightsApi([.ok(body)])

        let home = try await api.home()

        #expect(home.pendingExtraTimeRequests.map(\.id) == [requestId])
        #expect(home.pendingExtraTimeRequests.first?.requestedMinutes == 30)
        #expect(home.pendingExtraTimeRequests.first?.childName == nil)
    }

    @Test func aHomeWithoutTheListHasNoAsks() async throws {
        let body = bareHomeJSON.replacingOccurrences(of: #""pendingExtraTimeRequests":[],"#, with: "")
        let (api, _) = insightsApi([.ok(body)])

        let home = try await api.home()

        #expect(home.pendingExtraTimeRequests.isEmpty)
        #expect(home.children.count == 1)
    }

    // Review Focus 3: one unreadable ask must not blank the front door.
    @Test func aListThatCannotBeReadLeavesHomeStanding() async throws {
        let body = bareHomeJSON.replacingOccurrences(
            of: #""pendingExtraTimeRequests":[]"#,
            with: #""pendingExtraTimeRequests":[{"id":"not-a-uuid"}]"#
        )
        let (api, _) = insightsApi([.ok(body)])

        let home = try await api.home()

        #expect(home.pendingExtraTimeRequests.isEmpty)
        #expect(home.children.count == 1)
    }
}
