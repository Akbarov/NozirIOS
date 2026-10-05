import Foundation
import NozirInsights
import NozirNetworking

/// Answers daily and app-usage calls at once, except the numbered calls (1-based, per
/// kind) in `hanging`: those announce themselves and then wait until cancelled.
actor HangingInsights: InsightsService {
    private let hanging: Set<Int>
    private var dailyCalls = 0
    private var appCalls = 0
    private var asked: [String: CheckedContinuation<Void, Never>] = [:]
    private var askedAlready: Set<String> = []

    init(hanging: Set<Int>) {
        self.hanging = hanging
    }

    func waitUntilAsked(_ kind: String, _ number: Int) async {
        let key = "\(kind)\(number)"
        if askedAlready.contains(key) { return }
        await withCheckedContinuation { asked[key] = $0 }
    }

    private func announce(_ kind: String, _ number: Int) {
        let key = "\(kind)\(number)"
        askedAlready.insert(key)
        asked.removeValue(forKey: key)?.resume()
    }

    func appUsage(of childId: UUID, range: UsageRange) async throws -> AppBreakdown {
        appCalls += 1
        let number = appCalls
        announce("apps", number)
        if hanging.contains(number) { try await Task.sleep(for: .seconds(3600)) }
        return AppBreakdown(range: range, totalMinutes: 10, entries: [AppUsageEntry(packageId: "a", displayName: "", minutes: 10)])
    }

    func dailySummary(of childId: UUID, on date: LocalDate?) async throws -> InsightSummary {
        dailyCalls += 1
        let number = dailyCalls
        announce("daily", number)
        if hanging.contains(number) { try await Task.sleep(for: .seconds(3600)) }
        return insight(childId: childId, start: "2026-10-04", end: "2026-10-04")
    }

    func home() async throws -> ParentHome { throw offline }
    func weeklySummary(of childId: UUID, weekStart: LocalDate) async throws -> InsightSummary { throw offline }
    func dailyUsage(of childId: UUID, from: LocalDate, to: LocalDate) async throws -> [DailyUsage] { throw offline }
}
