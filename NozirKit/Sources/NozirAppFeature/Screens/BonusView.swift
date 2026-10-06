import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P12 as Android `BonusContent`: the ceiling at the top, then the tasks with
/// a switch each.
struct BonusView: View {
    @State private var model: BonusModel
    @Environment(\.l10n) private var l10n

    init(model: BonusModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                Text(BonusTexts.caption(childName: model.session.childName, l10n))
                    .nozirText(.body, color: NozirColor.textSecondary)
                if let config = model.config {
                    if model.session.isOffline {
                        NozirOfflineNotice(l10n.stateOfflineNotice)
                    }
                    ceilingCard(config)
                    NozirSectionTitle(l10n.bonusChallengesLabel)
                    if model.visibleChallenges.isEmpty {
                        NozirEmptyState(title: l10n.bonusEmptyTitle, message: l10n.bonusEmptyBody)
                    } else {
                        NozirCard {
                            ForEach(Array(model.visibleChallenges.enumerated()), id: \.element.id) { position, challenge in
                                if position > 0 { Divider() }
                                challengeRow(challenge)
                            }
                        }
                    }
                    RuleSaveFooter(
                        notice: model.notice,
                        message: model.message,
                        childName: model.session.childName,
                        isSaving: model.isSaving,
                        canSave: model.canSave
                    ) {
                        Task { await model.save() }
                    }
                } else if let failure = model.loadFailure ?? model.session.loadFailure {
                    NozirErrorState(
                        title: l10n.stateErrorTitle,
                        message: failure.text(l10n),
                        retryTitle: l10n.stateActionRetry
                    ) {
                        Task { await model.load() }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenBonusTimeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    private func ceilingCard(_ config: BonusConfig) -> some View {
        NozirCard {
            RuleMinuteSlider(
                title: l10n.bonusCeilingTitle,
                caption: l10n.bonusCeilingSubtitle,
                value: Binding(get: { config.maxDailyBonusMinutes }, set: { model.setCeiling($0) }),
                range: RuleMinuteRange.bonusCeiling,
                accessibilityLabel: l10n.bonusCeilingSlider,
                valueText: { BonusTexts.ceilingValue($0, l10n) }
            )
            if let note = BonusTexts.ceilingNote(config, l10n) {
                Text(note).nozirText(.bodySmall, color: NozirColor.textSecondary)
            }
        }
    }

    private func challengeRow(_ challenge: BonusChallenge) -> some View {
        let name = BonusTexts.name(challenge.kind, l10n) ?? ""
        return HStack(spacing: NozirSpacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).nozirText(.body)
                if let subtitle = BonusTexts.subtitle(challenge, l10n) {
                    Text(subtitle).nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
            }
            Spacer(minLength: NozirSpacing.small)
            Text(BonusTexts.minutes(challenge, l10n)).nozirText(.bodySmall, color: NozirColor.textSecondary)
            Toggle(l10n.bonusChallengeToggle(name), isOn: Binding(get: { challenge.enabled }, set: { model.setEnabled(challenge.id, $0) }))
                .labelsHidden()
                .tint(NozirColor.primary)
        }
        .frame(minHeight: NozirSize.control)
    }
}
