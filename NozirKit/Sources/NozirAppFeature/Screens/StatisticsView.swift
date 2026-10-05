import SwiftUI
import NozirDesignSystem
import NozirL10n

/// The Statistics tab's root: P07 for the chosen child, with the switcher when
/// there is more than one. One weekly model lives for the tab; choosing another
/// child tells it rather than building a new one.
struct StatisticsView: View {
    private let statistics: StatisticsModel
    private let makeWeekly: (UUID) -> WeeklyReportModel
    private let onAddChild: () -> Void
    private let onOpenApps: (UUID) -> Void
    @State private var weekly: WeeklyReportModel?
    @Environment(\.l10n) private var l10n

    init(
        statistics: StatisticsModel,
        makeWeekly: @escaping (UUID) -> WeeklyReportModel,
        onAddChild: @escaping () -> Void,
        onOpenApps: @escaping (UUID) -> Void
    ) {
        self.statistics = statistics
        self.makeWeekly = makeWeekly
        self.onAddChild = onAddChild
        self.onOpenApps = onOpenApps
    }

    var body: some View {
        Group {
            if statistics.childId != nil, let weekly {
                WeeklyReportView(model: weekly, switcher: switcher, onOpenApps: onOpenApps)
            } else if statistics.family.hasLoaded, statistics.childId == nil {
                ScrollView {
                    NozirEmptyState(
                        title: l10n.homeEmptyTitle,
                        message: l10n.homeEmptyBody,
                        actionTitle: l10n.homeEmptyAction,
                        action: onAddChild
                    )
                    .padding(NozirSpacing.medium)
                }
                .background(NozirColor.background.ignoresSafeArea())
                .navigationTitle(l10n.tabStatistics)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NozirColor.background.ignoresSafeArea())
            }
        }
        .task(id: statistics.childId) {
            guard let id = statistics.childId else { return }
            if let weekly {
                await weekly.setChild(id)
            } else {
                weekly = makeWeekly(id)
            }
        }
    }

    private var switcher: WeeklySwitcher? {
        guard statistics.showsSwitcher else { return nil }
        return WeeklySwitcher(
            children: statistics.switcherChildren,
            selection: Binding(
                get: { statistics.childId },
                set: { statistics.selectedChildId = $0 }
            )
        )
    }
}
