import Foundation
import Observation
import NozirFamily
import NozirInsights
import NozirNetworking

/// P16a (Android `SummaryLinkViewModel`): a notification names a summary by
/// its id alone; this asks the server which child and which day or week it
/// is, and answers with the step that opens it. Nothing is cached: every
/// visit is a tap, and a cache could only answer a new tap with an old one.
@MainActor
@Observable
final class SummaryLinkModel {
    enum Phase: Equatable {
        case loading
        /// Where the summary lives; the screen hands its place to this step.
        case resolved(SignedInView.HomeStep)
        /// 404 (removed, or another family's), a period this app does not
        /// know, or a child no longer in the family.
        case gone
        case failed(UserMessage)
    }

    let summaryId: UUID
    private(set) var phase: Phase = .loading

    private let insights: any InsightsService
    private let family: FamilyStore
    /// Only the newest lookup writes (spec §4.2).
    @ObservationIgnored private var generation = 0

    init(summaryId: UUID, insights: any InsightsService, family: FamilyStore) {
        self.summaryId = summaryId
        self.insights = insights
        self.family = family
    }

    /// On appear and on "Qayta urinish". A later call wins: an earlier answer
    /// that arrives after it is dropped, so the screen never navigates twice.
    func load() async {
        generation += 1
        let mine = generation
        phase = .loading
        let next: Phase
        do {
            let summary = try await insights.summary(id: summaryId)
            guard mine == generation else { return }
            next = try await step(for: summary).map(Phase.resolved) ?? .gone
        } catch is CancellationError {
            // Nothing to fall back to: offer a retry rather than a spinner nobody drives (plan deviation L10).
            next = .failed(.noConnection)
        } catch let failure as ApiFailure where failure.isNotFound {
            next = .gone
        } catch {
            next = .failed(UserMessage(error))
        }
        guard mine == generation else { return }
        phase = next
    }

    /// nil: nothing this app can open (spec §4.2).
    private func step(for summary: InsightSummary) async throws -> SignedInView.HomeStep? {
        guard let period = summary.period, let name = try await childName(summary.childId) else { return nil }
        switch period {
        case .daily:
            return .summary(summary.childId, name, date: summary.periodStart)
        case .weekly:
            return .weekly(summary.childId, weekStart: summary.periodStart)
        }
    }

    /// From the family list; when the child is not in it, the list is asked
    /// for once (plan deviation L1). A failed read is thrown, not "gone".
    private func childName(_ childId: UUID) async throws -> String? {
        if let child = family.child(childId) {
            return LocationTexts.present(child.displayName)
        }
        try await family.refresh()
        return family.child(childId).flatMap { LocationTexts.present($0.displayName) }
    }

    /// The link hands its place in Home's stack to the summary (spec §4.2):
    /// Back from that summary returns to where the parent tapped. When the
    /// link is no longer on top — the parent went back, or something else was
    /// opened over it — the path stays as it is (plan deviation L4).
    static func path(
        _ path: [SignedInView.HomeStep],
        replacing summaryId: UUID,
        with step: SignedInView.HomeStep
    ) -> [SignedInView.HomeStep] {
        guard path.last == .summaryLink(summaryId) else { return path }
        return Array(path.dropLast()) + [step]
    }
}
