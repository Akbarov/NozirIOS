import Foundation
import Observation
import NozirInsights
import NozirL10n
import NozirNetworking

/// P06. The daily summary first; then, for the "ask this week" line only, the
/// weekly summary of the week the day belongs to (plan deviation E2: only the
/// daily answer knows which day it is). A weekly failure is silent.
@MainActor
@Observable
final class DailySummaryModel {
    enum State: Equatable {
        case loading
        case loaded(InsightSummary)
        /// 404: the server writes a summary only for a finished day. An answer, not a fault.
        case notReady
        case failed(UserMessage)
    }

    let childId: UUID
    let childName: String
    private(set) var state: State = .loading
    private(set) var question: String?

    private let date: LocalDate?
    private let insights: any InsightsService
    /// The session's; nil never asks (previews, tests that do not care).
    private let reviewGate: ReviewGate?

    init(
        childId: UUID,
        childName: String,
        date: LocalDate? = nil,
        insights: any InsightsService,
        reviewGate: ReviewGate? = nil
    ) {
        self.childId = childId
        self.childName = childName
        self.date = date
        self.insights = insights
        self.reviewGate = reviewGate
    }

    /// A summary is on screen: the moment worth asking at (spec D3).
    var hasSummary: Bool {
        if case .loaded = state { return true }
        return false
    }

    /// Asked by the screen when `hasSummary` turns true. Only then is the gate
    /// touched; it answers yes once per install (plan deviation L8).
    func reviewIsDue() -> Bool {
        guard hasSummary, let reviewGate else { return false }
        return reviewGate.consumeIfDue()
    }

    /// On appear. A summary already read is not asked for again.
    func load() async {
        if case .loaded = state { return }
        // A stale "no connection" never stays up while it asks again.
        if case .failed = state { state = .loading }
        await fetch()
    }

    /// Pull to refresh or the retry button; a summary on screen stays while it is asked for again.
    func retry() async {
        if case .loaded = state {
            await fetch()
        } else {
            state = .loading
            await fetch()
        }
    }

    private func fetch() async {
        do {
            let summary = try await insights.dailySummary(of: childId, on: date)
            state = .loaded(summary)
            let weekly = try? await insights.weeklySummary(of: childId, weekStart: summary.periodEnd.monday)
            question = weekly?.conversationQuestion
        } catch is CancellationError {
            // Nothing on screen to fall back to: offer a retry rather than a spinner nobody drives.
            if state == .loading { state = .failed(.noConnection) }
        } catch let failure as ApiFailure where failure.isNotFound {
            state = .notReady
            question = nil
        } catch {
            state = .failed(UserMessage(error))
            question = nil
        }
    }

    /// "Ali bugun" — Android's label; the summary is about the last finished day.
    func title(_ l10n: L10n) -> String {
        l10n.dailySummaryChildToday(childName)
    }

    /// "Yakshanba, 4-oktabr" once the summary has said which day it is.
    func subtitle(_ l10n: L10n) -> String? {
        guard case .loaded(let summary) = state else { return nil }
        return DateTexts.weekdayAndDate(summary.periodEnd, l10n)
    }
}
