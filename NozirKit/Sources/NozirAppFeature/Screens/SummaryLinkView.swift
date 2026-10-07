import SwiftUI
import NozirDesignSystem
import NozirL10n

/// P16a as Android `SummaryLinkContent`: a spinner while the server says
/// which summary the link names, "Bu xulosa endi mavjud emas" when there is
/// none, the error state with "Qayta urinish" on a failure. Once resolved the
/// screen is replaced by the summary at once (spec §5).
struct SummaryLinkView: View {
    @State private var model: SummaryLinkModel
    private let onResolved: (SignedInView.HomeStep) -> Void
    @Environment(\.l10n) private var l10n

    init(model: SummaryLinkModel, onResolved: @escaping (SignedInView.HomeStep) -> Void) {
        _model = State(initialValue: model)
        self.onResolved = onResolved
    }

    var body: some View {
        ScrollView {
            content
                .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenSummaryLinkTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onChange(of: model.phase, initial: true) { _, phase in
            if case .resolved(let step) = phase {
                onResolved(step)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading, .resolved:
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        case .gone:
            NozirEmptyState(title: l10n.summaryLinkGoneTitle, message: l10n.summaryLinkGoneBody)
        case .failed(let message):
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: message.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        }
    }
}
