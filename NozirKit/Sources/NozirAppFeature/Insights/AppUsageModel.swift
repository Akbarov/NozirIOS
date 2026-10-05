import Foundation
import Observation
import NozirInsights
import NozirL10n

/// P08 for one child. The view binds `range` and calls `load()` whenever it
/// changes; an answer for a range that is no longer chosen is dropped, so a
/// slow "Bugun" can never overwrite "7 kun".
@MainActor
@Observable
final class AppUsageModel {
    enum State: Equatable {
        case loading
        case loaded(AppBreakdown)
        case failed(UserMessage)
    }

    let childId: UUID
    var range: UsageRange = .today
    private(set) var state: State = .loading
    var showsTable = false

    private let insights: any InsightsService
    @ObservationIgnored private var generation = 0
    /// The range the `.loaded` state is about; a refresh of the same range keeps it on screen.
    @ObservationIgnored private var loadedRange: UsageRange?

    init(childId: UUID, insights: any InsightsService) {
        self.childId = childId
        self.insights = insights
    }

    func load() async {
        generation += 1
        let mine = generation
        let asked = range
        var keepsContent = false
        if case .loaded = state, loadedRange == asked {
            keepsContent = true
        } else {
            state = .loading
        }
        do {
            let breakdown = try await insights.appUsage(of: childId, range: asked)
            guard mine == generation else { return }
            state = .loaded(breakdown)
            loadedRange = asked
        } catch is CancellationError {
            // Nothing on screen to fall back to: offer a retry rather than a spinner nobody drives.
            guard mine == generation, !keepsContent else { return }
            state = .failed(.noConnection)
        } catch {
            guard mine == generation else { return }
            state = .failed(UserMessage(error))
        }
    }

    /// Top four, then "Boshqalar" last.
    var entries: [AppUsageEntry] {
        guard case .loaded(let breakdown) = state else { return [] }
        return AppUsageFolding.folded(breakdown.entries)
    }

    var total: Int {
        guard case .loaded(let breakdown) = state else { return 0 }
        return breakdown.totalMinutes
    }

    var isEmpty: Bool {
        guard case .loaded = state else { return false }
        return entries.isEmpty
    }

    nonisolated static func name(of entry: AppUsageEntry, _ l10n: L10n) -> String {
        entry.isOtherApps ? l10n.appUsageOther : AppUsageFolding.friendlyName(packageId: entry.packageId, reported: entry.displayName)
    }

    /// Which of the four series colours; nil is the grey of "Boshqalar".
    nonisolated static func colorIndex(of entry: AppUsageEntry, at index: Int) -> Int? {
        guard !entry.isOtherApps, index < AppUsageFolding.keptApps else { return nil }
        return index
    }

    /// The stacked bar as VoiceOver reads it.
    nonisolated static func chartDescription(_ entries: [AppUsageEntry], _ l10n: L10n) -> String {
        let spoken = entries.map { l10n.appUsageChartEntry(name(of: $0, l10n), Durations.short($0.minutes, l10n)) }
        return l10n.appUsageChartDescription(spoken.joined(separator: l10n.weeklyChartDaySeparator))
    }

    nonisolated static func rangeTitle(_ range: UsageRange, _ l10n: L10n) -> String {
        switch range {
        case .today: l10n.rangeToday
        case .lastSevenDays: l10n.rangeSevenDays
        case .lastThirtyDays: l10n.rangeThirtyDays
        }
    }
}
