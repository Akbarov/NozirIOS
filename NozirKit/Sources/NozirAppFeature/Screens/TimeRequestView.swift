import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P17 as Android `TimeRequestContent`: who asked and when, their words, two
/// plain facts, then the answer — the buttons, the reason field a refusal
/// opens, or the answer once given (including one the other parent gave).
struct TimeRequestView: View {
    @State private var model: TimeRequestModel
    @Environment(\.l10n) private var l10n
    @Environment(\.scenePhase) private var scenePhase

    init(model: TimeRequestModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.small) {
                if model.isOffline {
                    NozirOfflineNotice(l10n.stateOfflineNotice)
                }
                content
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenTimeRequestTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        // Back from another app: the other parent may have answered meanwhile.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.load() }
            }
        }
        .nozirToast(Binding(
            get: { model.toast?.text(l10n) },
            set: { if $0 == nil { model.toast = nil } }
        ))
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        case .missing:
            NozirEmptyState(title: l10n.timeRequestEmptyTitle, message: l10n.timeRequestEmptyBody)
        case .failed(let message):
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: message.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        case .ready:
            if let request = model.request {
                header(request)
                reasonCard(request)
                if let context = TimeRequestTexts.context(
                    usedMinutesToday: model.usedMinutesToday,
                    requestsInLastSevenDays: request.requestsInLastSevenDays,
                    l10n
                ) {
                    NozirCard {
                        Text(context).nozirText(.bodySmall, color: NozirColor.textSecondary)
                    }
                }
                decision(request)
            }
        }
    }

    /// Who, how much and when.
    private func header(_ request: ExtraTimeRequest) -> some View {
        NozirCard {
            HStack(spacing: NozirSpacing.compact) {
                NozirAvatar(
                    name: request.childName ?? "",
                    tone: .forKey(nil, position: 0),
                    fallbackInitial: l10n.previewAvatarInitial,
                    size: 44
                )
                VStack(alignment: .leading, spacing: NozirSpacing.extraSmall) {
                    Text(TimeRequestTexts.header(request, l10n)).nozirText(.titleSmall)
                    Text(TimeRequestTexts.headerMeta(request, l10n))
                        .nozirText(.bodySmall, color: NozirColor.primaryAccent)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    /// The child's own words, quoted and otherwise untouched.
    private func reasonCard(_ request: ExtraTimeRequest) -> some View {
        NozirCard {
            Text(l10n.timeRequestReasonLabel)
                .nozirText(.label, color: NozirColor.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Text(TimeRequestTexts.reason(request, l10n)).nozirText(.body)
        }
    }

    @ViewBuilder
    private func decision(_ request: ExtraTimeRequest) -> some View {
        if request.status != .pending {
            answeredCard(request)
        } else if model.isWritingDecline {
            declineCard
        } else {
            actions(request)
            noteCard(request)
        }
    }

    /// Yes, a smaller amount, or no — one above the other, so large text never cuts a label.
    private func actions(_ request: ExtraTimeRequest) -> some View {
        VStack(spacing: NozirSpacing.small) {
            NozirButton(
                TimeRequestTexts.approveTitle(request, l10n),
                size: .callToAction,
                isLoading: model.deciding == .approve
            ) {
                Task { await model.approve() }
            }
            if let partial = model.partialMinutes {
                NozirButton(
                    TimeRequestTexts.partialTitle(partial, of: request, l10n),
                    variant: .secondary,
                    isLoading: model.deciding == .partial
                ) {
                    Task { await model.approvePartial() }
                }
            }
            NozirButton(l10n.timeRequestActionDecline, variant: .ghost) { model.startDecline() }
        }
        .disabled(model.isDeciding)
    }

    /// Said once, before it is needed; for a bedtime, that a yes is for tonight only.
    private func noteCard(_ request: ExtraTimeRequest) -> some View {
        NozirCard {
            HStack(alignment: .top, spacing: NozirSpacing.small) {
                Text(l10n.glyphInfo)
                    .nozirText(.label, color: NozirColor.card)
                    .frame(width: NozirSize.icon, height: NozirSize.icon)
                    .background(Circle().fill(NozirColor.primaryAccent))
                    .accessibilityHidden(true)
                Text(TimeRequestTexts.note(request, l10n)).nozirText(.bodySmall)
            }
        }
    }

    private var declineCard: some View {
        NozirCard {
            NozirTextField(
                l10n.timeRequestDeclineLabel,
                text: Binding(get: { model.declineNote }, set: { model.updateDeclineNote($0) }),
                placeholder: l10n.timeRequestDeclinePlaceholder
            )
            .disabled(model.isDeciding)
            Text(l10n.timeRequestDeclineHint).nozirText(.bodySmall, color: NozirColor.textSecondary)
            // Side by side when both fit; stacked at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: NozirSpacing.small) { declineButtons }
                VStack(spacing: NozirSpacing.small) { declineButtons }
            }
        }
    }

    @ViewBuilder
    private var declineButtons: some View {
        NozirButton(l10n.timeRequestDeclineBack, variant: .secondary) { model.cancelDecline() }
            .disabled(model.isDeciding)
        NozirButton(l10n.timeRequestDeclineConfirm, isLoading: model.deciding == .decline) {
            Task { await model.confirmDecline() }
        }
        .disabled(model.isDeciding)
    }

    /// The answer, and a refusal's reason shown back as the child reads it.
    @ViewBuilder
    private func answeredCard(_ request: ExtraTimeRequest) -> some View {
        if let outcome = TimeRequestTexts.outcome(request, l10n) {
            NozirCard {
                Text(outcome)
                    .nozirText(.titleSmall, color: request.status == .approved ? NozirColor.goodContent : NozirColor.textPrimary)
                if let note = TimeRequestTexts.decisionNote(request, l10n) {
                    Text(note).nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
