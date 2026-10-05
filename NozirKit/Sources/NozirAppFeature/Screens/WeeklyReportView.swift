import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// The Statistics tab's child switcher, when there is more than one child.
struct WeeklySwitcher {
    let children: [NozirSwitcherChild]
    let selection: Binding<UUID?>
}

/// P07 as Android `WeeklyReportScreen`: one page per week, swiped or stepped
/// with ‹ ›, this week last.
struct WeeklyReportView: View {
    @State private var model: WeeklyReportModel
    private let switcher: WeeklySwitcher?
    private let onOpenApps: (UUID) -> Void
    @Environment(\.l10n) private var l10n

    init(model: WeeklyReportModel, switcher: WeeklySwitcher?, onOpenApps: @escaping (UUID) -> Void) {
        _model = State(initialValue: model)
        self.switcher = switcher
        self.onOpenApps = onOpenApps
    }

    var body: some View {
        VStack(spacing: NozirSpacing.small) {
            if let switcher {
                NozirChildSwitcher(
                    children: switcher.children,
                    selection: switcher.selection,
                    fallbackInitial: l10n.previewAvatarInitial
                )
                .padding(.horizontal, NozirSpacing.medium)
            }
            weekHeader
                .padding(.horizontal, NozirSpacing.medium)
            TabView(selection: $model.selectedWeek) {
                ForEach(model.weeks, id: \.self) { week in
                    ScrollView {
                        page(week)
                            .padding(NozirSpacing.medium)
                    }
                    .tag(week)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenWeeklyReportTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.selectedWeek) { await model.appear() }
    }

    private var weekHeader: some View {
        HStack {
            Button {
                if let previous = model.week(before: model.selectedWeek) { model.selectedWeek = previous }
            } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .disabled(model.week(before: model.selectedWeek) == nil)
            .accessibilityLabel(l10n.contentDescriptionPreviousWeek)
            Spacer()
            VStack(spacing: 2) {
                Text(model.title(of: model.selectedWeek, l10n)).nozirText(.titleSmall)
                Text(WeeklyReportModel.range(of: model.selectedWeek, l10n))
                    .nozirText(.bodySmall, color: NozirColor.textTertiary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button {
                if let next = model.week(after: model.selectedWeek) { model.selectedWeek = next }
            } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(model.week(after: model.selectedWeek) == nil)
            .accessibilityLabel(l10n.contentDescriptionNextWeek)
        }
        .tint(NozirColor.primaryAccent)
    }

    @ViewBuilder
    private func page(_ week: LocalDate) -> some View {
        switch model.pages[week] {
        case .loaded(let page)?:
            loaded(page)
        case .failed(let message)?:
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: message.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.retry(week) }
            }
        case .loading?, nil:
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        }
    }

    @ViewBuilder
    private func loaded(_ page: WeeklyReportModel.Page) -> some View {
        VStack(alignment: .leading, spacing: NozirSpacing.large) {
            if WeeklyReportModel.isEmpty(page) {
                NozirEmptyState(title: l10n.weeklyEmptyTitle, message: l10n.weeklyEmptyBody)
            } else {
                let columns = WeeklyReportModel.columns(page, l10n)
                NozirCard {
                    Text(l10n.weeklyChartLabel).nozirText(.label, color: NozirColor.textSecondary)
                    NozirColumnChart(
                        columns: columns,
                        accessibilityLabel: WeeklyReportModel.chartDescription(columns, l10n)
                    )
                    if let peakLine = WeeklyReportModel.peakLine(page, l10n) {
                        Text(peakLine).nozirText(.bodySmall, color: NozirColor.textSecondary)
                    }
                }
                if !page.observations.isEmpty {
                    NozirCard {
                        Text(l10n.weeklyObservationsLabel).nozirText(.label, color: NozirColor.textSecondary)
                        ForEach(Array(page.observations.enumerated()), id: \.offset) { _, observation in
                            HStack(alignment: .firstTextBaseline, spacing: NozirSpacing.small) {
                                Circle()
                                    .fill(page.risk.content)
                                    .frame(width: 8, height: 8)
                                    .accessibilityHidden(true)
                                Text(observation).nozirText(.body)
                            }
                        }
                    }
                }
            }
            NozirButton(l10n.weeklyActionApps, variant: .secondary) {
                onOpenApps(model.childId)
            }
        }
    }
}
