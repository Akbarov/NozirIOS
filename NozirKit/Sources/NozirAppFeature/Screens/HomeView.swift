import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P05 as Android `HomeContent`: the SOS banner, the offline notice, then the
/// family (empty, one child, or many). P15–P18 links are not in this slice.
struct HomeView: View {
    @State private var model: HomeModel
    private let reloadToken: Int
    private let emergencyNumber: () -> String?
    private let onOpenSummary: (UUID, String) -> Void
    private let onAddChild: () -> Void
    @Environment(\.l10n) private var l10n
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSos = false

    init(
        model: HomeModel,
        reloadToken: Int,
        emergencyNumber: @escaping () -> String?,
        onOpenSummary: @escaping (UUID, String) -> Void,
        onAddChild: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.reloadToken = reloadToken
        self.emergencyNumber = emergencyNumber
        self.onOpenSummary = onOpenSummary
        self.onAddChild = onAddChild
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.small) {
                if let alert = model.sosAlert(emergencyNumber: emergencyNumber()) {
                    SosBanner(alert: alert) { showsSos = true }
                }
                if model.notice == .offline {
                    NozirOfflineNotice(l10n.stateOfflineNotice)
                }
                content
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenHomeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reloadToken) { await model.appear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.load() }
            }
        }
        .refreshable { await model.load() }
        .sheet(isPresented: $showsSos) {
            if let alert = model.sosAlert(emergencyNumber: emergencyNumber()) {
                SosSheet(alert: alert)
                    .environment(\.l10n, l10n)
                    .environment(\.locale, locale)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let home = model.home {
            if case .message(let message) = model.notice {
                NozirInlineMessage(message.text(l10n))
            }
            switch home.children.count {
            case 0:
                NozirEmptyState(
                    title: l10n.homeEmptyTitle,
                    message: l10n.homeEmptyBody,
                    actionTitle: l10n.homeEmptyAction,
                    action: onAddChild
                )
            case 1:
                singleChild(home, home.children[0])
            default:
                family(home)
            }
        } else if let failure = model.failure {
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: failure.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
        }
    }

    // MARK: One child (P05a)

    @ViewBuilder
    private func singleChild(_ home: ParentHome, _ card: ChildHomeCard) -> some View {
        HStack(spacing: NozirSpacing.compact) {
            NozirAvatar(name: card.displayName, tone: model.tone(of: card), fallbackInitial: l10n.previewAvatarInitial, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.nameAndAge(of: card, l10n)).nozirText(.titleSmall)
                Text(l10n.homeTodayAndDate(DateTexts.dayAndMonth(home.date, l10n)))
                    .nozirText(.bodySmall, color: NozirColor.textTertiary)
            }
            Spacer(minLength: 0)
            statusChip(card.statusLevel)
        }
        .accessibilityElement(children: .combine)
        if let sentence = card.summarySentence {
            NozirCard {
                Text(l10n.homeSummaryLabel).nozirText(.label, color: NozirColor.textSecondary)
                Text(sentence).nozirText(.body)
                Button(l10n.homeSummaryAction) { onOpenSummary(card.id, card.displayName) }
                    .font(.system(size: 15, weight: .semibold))
                    .tint(NozirColor.primaryAccent)
            }
        }
        HStack(alignment: .top, spacing: NozirSpacing.small) {
            statTile(
                label: l10n.homeStatScreenTime,
                value: Durations.short(card.usedMinutes, l10n),
                caption: l10n.homeStatOfLimit(Durations.short(card.limitMinutes, l10n))
            )
            statTile(
                label: l10n.homeStatPlace,
                value: HomeModel.placeTitle(card, l10n),
                caption: HomeModel.placeCaption(card, l10n)
            )
        }
    }

    private func statTile(label: String, value: String, caption: String?) -> some View {
        NozirCard {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).nozirText(.label, color: NozirColor.textSecondary)
                Text(value).nozirText(.titleSmall)
                if let caption {
                    Text(caption).nozirText(.bodySmall, color: NozirColor.textTertiary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func statusChip(_ level: StatusLevel) -> some View {
        HStack(spacing: NozirSpacing.extraSmall) {
            NozirStatusDot(level.designLevel)
            Text(level.label(l10n)).nozirText(.bodySmall, color: level.content)
        }
        .padding(.horizontal, NozirSpacing.small)
        .padding(.vertical, NozirSpacing.extraSmall)
        .background(Capsule().fill(level.container))
    }

    // MARK: Many children (P05b, P05c)

    @ViewBuilder
    private func family(_ home: ParentHome) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(l10n.homeFamilyTitle).nozirText(.titleLarge)
            Spacer()
            Text(DateTexts.dayAndMonth(home.date, l10n)).nozirText(.bodySmall, color: NozirColor.textTertiary)
        }
        NozirChildSwitcher(
            children: model.switcherChildren,
            selection: $model.filter,
            allTitle: l10n.homeShowAllChildren,
            allAccessibilityLabel: l10n.homeShowAllChildrenDescription,
            addTitle: l10n.homeAddChild,
            onAdd: onAddChild,
            fallbackInitial: l10n.previewAvatarInitial
        )
        ForEach(model.visible) { card in
            Button {
                onOpenSummary(card.id, card.displayName)
            } label: {
                childCard(card)
            }
            .buttonStyle(.plain)
            .accessibilityHint(l10n.homeSummaryAction)
        }
        if model.showsAttentionNote {
            Text(l10n.homeNotComparedNote)
                .nozirText(.bodySmall, color: NozirColor.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else if let sentence = home.familySummary {
            NozirCard {
                Text(l10n.homeFamilySummaryLabel).nozirText(.label, color: NozirColor.textSecondary)
                Text(sentence).nozirText(.body)
            }
        }
    }

    @ViewBuilder
    private func childCard(_ card: ChildHomeCard) -> some View {
        switch model.style(of: card) {
        case .attention:
            NozirCard(tone: .attention) {
                HStack(spacing: NozirSpacing.small) {
                    statusMark(.action)
                    NozirAvatar(name: card.displayName, tone: model.tone(of: card), fallbackInitial: l10n.previewAvatarInitial, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.nameAndAge(of: card, l10n)).nozirText(.body)
                        Text(HomeModel.usageAndPlace(card, l10n)).nozirText(.bodySmall, color: NozirColor.attentionContent)
                    }
                    Spacer(minLength: 0)
                }
                if let sentence = card.summarySentence {
                    Text(sentence).nozirText(.bodySmall)
                }
                Text(l10n.homeAttentionAction).nozirText(.bodySmall, color: NozirColor.actionContent)
            }
        case .quiet:
            NozirCard {
                row(card, subtitle: HomeModel.usageAndRules(card, l10n), avatarSize: 36)
            }
        case .plain:
            NozirCard {
                row(card, subtitle: HomeModel.usageAndPlace(card, l10n), avatarSize: 40)
                if let sentence = card.summarySentence {
                    Divider()
                    Text(sentence).nozirText(.bodySmall)
                }
            }
        }
    }

    private func row(_ card: ChildHomeCard, subtitle: String, avatarSize: CGFloat) -> some View {
        HStack(spacing: NozirSpacing.compact) {
            NozirAvatar(name: card.displayName, tone: model.tone(of: card), fallbackInitial: l10n.previewAvatarInitial, size: avatarSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.nameAndAge(of: card, l10n)).nozirText(.body)
                Text(subtitle).nozirText(.bodySmall, color: NozirColor.textSecondary)
            }
            Spacer(minLength: 0)
            statusMark(card.statusLevel)
        }
    }

    /// Android `ChildStatusMark`: the level's glyph in its colours; the label is
    /// what VoiceOver reads.
    private func statusMark(_ level: StatusLevel) -> some View {
        Text(level.glyph(l10n))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(level.content)
            .frame(width: 22, height: 22)
            .background(Circle().fill(level.container))
            .accessibilityLabel(level.label(l10n))
    }
}
