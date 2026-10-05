import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P08 as Android `AppUsageScreen`: a range, the total, a bar of shares with
/// its legend and per-app rows; or the same figures as a table.
struct AppUsageView: View {
    @State private var model: AppUsageModel
    @Environment(\.l10n) private var l10n

    init(model: AppUsageModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                Picker(l10n.appUsageTitle, selection: $model.range) {
                    ForEach(UsageRange.allCases, id: \.self) { range in
                        Text(AppUsageModel.rangeTitle(range, l10n)).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                content
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenAppUsageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.range) { await model.load() }
        .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        case .failed(let message):
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: message.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        case .loaded:
            if model.isEmpty {
                NozirEmptyState(title: l10n.appUsageEmptyTitle, message: l10n.appUsageEmptyBody)
            } else {
                Text(l10n.appUsageTotal(Durations.short(model.total, l10n))).nozirText(.titleLarge)
                if model.showsTable {
                    table
                } else {
                    chart
                }
                NozirButton(model.showsTable ? l10n.appUsageActionChart : l10n.appUsageActionTable, variant: .ghost) {
                    model.showsTable.toggle()
                }
            }
        }
    }

    private func color(_ entry: AppUsageEntry, at index: Int) -> Color {
        AppUsageModel.colorIndex(of: entry, at: index).map { NozirColor.chartSeries[$0] } ?? NozirColor.chartOther
    }

    private var chart: some View {
        let entries = model.entries
        let shares = AppUsageModel.barFractions(entries, total: model.total)
        let fractions = ChartMath.fractions(entries.map(\.minutes))
        return VStack(alignment: .leading, spacing: NozirSpacing.large) {
            NozirCard {
                NozirStackedBar(segments: entries.enumerated().map { index, entry in
                    NozirChartSegment(id: index, fraction: shares[index], color: color(entry, at: index))
                })
                .accessibilityElement()
                .accessibilityLabel(AppUsageModel.chartDescription(entries, l10n))
                NozirLegend(items: entries.enumerated().map { index, entry in
                    NozirLegendItem(
                        id: index,
                        color: color(entry, at: index),
                        label: AppUsageModel.name(of: entry, l10n),
                        valueLabel: l10n.appUsageSharePercent(AppUsageFolding.sharePercent(entry.minutes, of: model.total))
                    )
                })
            }
            NozirCard {
                ForEach(Array(entries.enumerated()), id: \.element) { index, entry in
                    VStack(alignment: .leading, spacing: NozirSpacing.extraSmall) {
                        HStack {
                            Text(AppUsageModel.name(of: entry, l10n)).nozirText(.body)
                            Spacer()
                            Text(Durations.short(entry.minutes, l10n)).nozirText(.bodySmall, color: NozirColor.textSecondary)
                        }
                        NozirProgressBar(fraction: fractions[index], color: color(entry, at: index))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var table: some View {
        NozirCard {
            Grid(alignment: .leading, horizontalSpacing: NozirSpacing.medium, verticalSpacing: NozirSpacing.small) {
                GridRow {
                    Text(l10n.appUsageTableApp).nozirText(.label, color: NozirColor.textSecondary)
                    Text(l10n.appUsageTableTime).nozirText(.label, color: NozirColor.textSecondary)
                        .gridColumnAlignment(.trailing)
                    Text(l10n.appUsageTableShare).nozirText(.label, color: NozirColor.textSecondary)
                        .gridColumnAlignment(.trailing)
                }
                Divider()
                ForEach(model.entries, id: \.self) { entry in
                    GridRow {
                        Text(AppUsageModel.name(of: entry, l10n)).nozirText(.body)
                        Text(Durations.short(entry.minutes, l10n)).nozirText(.body)
                        Text(l10n.appUsageSharePercent(AppUsageFolding.sharePercent(entry.minutes, of: model.total))).nozirText(.body)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
