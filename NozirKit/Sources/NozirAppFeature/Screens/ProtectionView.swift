import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P18 as Android `ProtectionContent`: the offline notice, the summary card,
/// the stale note, the permissions, then — only when something is not granted —
/// the steps for this phone and the button that sends them to it.
struct ProtectionView: View {
    @State private var model: ProtectionModel
    @Environment(\.l10n) private var l10n
    @Environment(\.scenePhase) private var scenePhase

    init(model: ProtectionModel) {
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
        .navigationTitle(l10n.screenProtectionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        // The tick under the button is silent for VoiceOver without this.
        .onChange(of: model.wereInstructionsSent) { _, sent in
            if sent {
                AccessibilityNotification.Announcement(l10n.protectionSendSent).post()
            }
        }
        // Back from another app (spec D5): the child may have fixed it meanwhile.
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
            NozirEmptyState(title: l10n.protectionNoChildTitle, message: l10n.protectionNoChildBody)
        case .failed(let message):
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: message.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        case .ready:
            if let status = model.status {
                summaryCard(status)
                if let note = ProtectionTexts.staleNote(status, now: Date(), l10n) {
                    NozirOfflineNotice(note)
                }
                permissionsCard(status)
                fix(status)
            }
        }
    }

    /// Where protection stands, in one line, before any list of toggles.
    private func summaryCard(_ status: ProtectionStatus) -> some View {
        NozirCard(tone: ProtectionTexts.cardTone(status.level)) {
            HStack(spacing: NozirSpacing.compact) {
                ProtectionShield(level: status.level)
                VStack(alignment: .leading, spacing: NozirSpacing.extraSmall) {
                    Text(ProtectionTexts.levelTitle(status.level, l10n))
                        .nozirText(.titleSmall)
                        .accessibilityAddTraits(.isHeader)
                    Text(ProtectionTexts.summaryBody(status, l10n))
                        .nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// In the order the child app asked for them (plan deviation P5: the card's heading).
    @ViewBuilder
    private func permissionsCard(_ status: ProtectionStatus) -> some View {
        if status.permissions.isEmpty {
            NozirEmptyState(title: l10n.protectionEmptyTitle, message: l10n.protectionEmptyBody)
        } else {
            NozirCard {
                Text(l10n.protectionPermissionsLabel)
                    .nozirText(.label, color: NozirColor.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(status.permissions.enumerated()), id: \.offset) { entry in
                    if entry.offset > 0 {
                        Divider()
                    }
                    permissionRow(entry.element)
                }
            }
        }
    }

    /// The dot, the word and its colour say the same thing; VoiceOver reads the words.
    private func permissionRow(_ permission: ProtectionPermission) -> some View {
        let level = ProtectionTexts.dotLevel(permission)
        return HStack(spacing: NozirSpacing.compact) {
            NozirStatusDot(level)
            VStack(alignment: .leading, spacing: 2) {
                Text(ProtectionTexts.name(permission.kind, l10n)).nozirText(.body)
                Text(ProtectionTexts.stateLine(permission, l10n)).nozirText(.bodySmall, color: color(level))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func color(_ level: NozirStatusLevel) -> Color {
        switch level {
        case .good: NozirColor.goodContent
        case .attention: NozirColor.attentionContent
        case .action: NozirColor.actionContent
        case .critical: NozirColor.criticalContent
        }
    }

    /// Nothing when everything works: an "all fine" evening ends at the list.
    @ViewBuilder
    private func fix(_ status: ProtectionStatus) -> some View {
        if let instruction = ProtectionTexts.instruction(status, childName: model.childName, l10n) {
            NozirCard {
                Text(l10n.protectionInstructionLabel)
                    .nozirText(.label, color: NozirColor.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Text(instruction).nozirText(.body)
            }
            NozirButton(
                ProtectionTexts.sendTitle(childName: model.childName, l10n),
                size: .callToAction,
                isLoading: model.isSending
            ) {
                Task { await model.sendInstructions() }
            }
            .disabled(model.isSending)
            if model.wereInstructionsSent {
                Text(l10n.protectionSendSent).nozirText(.bodySmall, color: NozirColor.goodContent)
            }
        }
    }
}
