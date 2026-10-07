import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n
import StoreKit

/// P06 as Android `DailySummaryScreen`: paragraphs, a recommendation, a
/// question for the week, the "no messages were read" promise, and the way on
/// to the weekly report.
struct DailySummaryView: View {
    @State private var model: DailySummaryModel
    private let onEditChild: () -> Void
    private let onOpenWeekly: () -> Void
    @Environment(\.l10n) private var l10n
    @Environment(\.requestReview) private var requestReview

    init(model: DailySummaryModel, onEditChild: @escaping () -> Void, onOpenWeekly: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onEditChild = onEditChild
        self.onOpenWeekly = onOpenWeekly
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                header
                content
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenDailySummaryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onEditChild) { Image(systemName: "pencil") }
                    .accessibilityLabel(l10n.contentDescriptionChildDetails)
            }
        }
        .task { await model.load() }
        .refreshable { await model.retry() }
        // Spec D3: the parent has just been given what they opened the app
        // for. The gate allows this once per install; Apple decides the rest.
        .onChange(of: model.hasSummary, initial: true) { _, hasSummary in
            if hasSummary, model.reviewIsDue() {
                requestReview()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.title(l10n)).nozirText(.titleLarge)
            if let subtitle = model.subtitle(l10n) {
                Text(subtitle).nozirText(.bodySmall, color: NozirColor.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        case .notReady:
            NozirEmptyState(title: l10n.dailySummaryEmptyTitle, message: l10n.dailySummaryEmptyBody)
            weeklyButton
        case .failed(let message):
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: message.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.retry() }
            }
        case .loaded(let summary):
            loaded(summary)
        }
    }

    @ViewBuilder
    private func loaded(_ summary: InsightSummary) -> some View {
        NozirCard {
            ForEach(Array(summary.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph).nozirText(.body)
            }
        }
        if let recommendation = summary.recommendation {
            NozirCard {
                Text(l10n.dailySummaryRecommendationLabel).nozirText(.label, color: NozirColor.textSecondary)
                Text(recommendation).nozirText(.body)
            }
        }
        if let question = model.question {
            NozirCard {
                Text(l10n.dailySummaryQuestionLabel).nozirText(.label, color: NozirColor.textSecondary)
                Text(question).nozirText(.body)
            }
        }
        HStack(alignment: .top, spacing: NozirSpacing.small) {
            Image(systemName: "lock.fill")
                .foregroundStyle(NozirColor.textTertiary)
                .accessibilityHidden(true)
            Text(l10n.dailySummaryNotice + " " + l10n.dailySummaryNoticePromise)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
        weeklyButton
    }

    private var weeklyButton: some View {
        NozirButton(l10n.dailySummaryActionWeekly, variant: .secondary, action: onOpenWeekly)
    }
}
