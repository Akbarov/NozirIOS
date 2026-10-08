import Foundation

/// Everything the home and report screens ask the server. `InsightsApi` is the
/// real one; screen-model tests use a scripted fake.
public protocol InsightsService: Sendable {
    func home() async throws -> ParentHome
    /// nil: the latest finished day. A missing summary is a 404 (`ApiFailure.isNotFound`).
    func dailySummary(of childId: UUID, on date: LocalDate?) async throws -> InsightSummary
    func weeklySummary(of childId: UUID, weekStart: LocalDate) async throws -> InsightSummary
    /// The summary a notification names (P16a). Not found or another family's
    /// is a 404 (`ApiFailure.isNotFound`). The server marks it read.
    func summary(id: UUID) async throws -> InsightSummary
    /// Both ends included; the server fills days without data with zero.
    func dailyUsage(of childId: UUID, from: LocalDate, to: LocalDate) async throws -> [DailyUsage]
    func appUsage(of childId: UUID, range: UsageRange) async throws -> AppBreakdown
}
