import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P09 for one child (Android `DailyLimitContent`): the limit, the trust
/// ladder, the notice, the other rules and "Saqlash"; or the state instead.
struct DailyLimitSection: View {
    private let model: DailyLimitModel
    private let onOpen: (RuleScreen) -> Void
    @Environment(\.l10n) private var l10n

    init(model: DailyLimitModel, onOpen: @escaping (RuleScreen) -> Void) {
        self.model = model
        self.onOpen = onOpen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.large) {
            if let snapshot = model.session.snapshot, let values = model.values {
                if model.session.isOffline {
                    NozirOfflineNotice(l10n.stateOfflineNotice)
                }
                if model.session.isFrozen {
                    FrozenChildCard(isMakingActive: model.session.isMakingActive) {
                        Task { await model.session.makeActive() }
                    }
                    if let message = model.session.message {
                        NozirInlineMessage(message.text(l10n))
                    }
                }
                limitCard(values).disabled(model.session.isFrozen)
                trustCard(values).disabled(model.session.isFrozen)
                Text(RuleTexts.limitNotice(childName: model.session.childName, l10n))
                    .nozirText(.bodySmall, color: NozirColor.textSecondary)
                otherRules(snapshot, isEnabled: !model.session.isFrozen)
                if !model.session.isFrozen {
                    RuleSaveFooter(
                        notice: model.notice,
                        message: model.message,
                        childName: model.session.childName,
                        isSaving: model.isSaving,
                        canSave: model.canSave
                    ) {
                        Task { await model.save() }
                    }
                }
            } else if let failure = model.session.loadFailure {
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
    }

    private func limitCard(_ values: DailyLimitValues) -> some View {
        NozirCard {
            Text(l10n.dailyLimitTitle).nozirText(.titleSmall)
            RuleMinuteSlider(
                title: model.isSameEveryDay ? l10n.dailyLimitEveryDay : l10n.dailyLimitSchoolDays,
                caption: model.isSameEveryDay ? nil : l10n.dailyLimitSchoolDaysRange,
                value: Binding(get: { values.schoolDayMinutes }, set: { model.setSchoolDayMinutes($0) }),
                range: RuleMinuteRange.dailyLimit,
                accessibilityLabel: l10n.dailyLimitSliderSchool
            )
            Toggle(l10n.dailyLimitEveryDaySame, isOn: Binding(get: { model.isSameEveryDay }, set: { model.setSameEveryDay($0) }))
                .tint(NozirColor.primary)
            if !model.isSameEveryDay {
                RuleMinuteSlider(
                    title: l10n.dailyLimitWeekend,
                    caption: l10n.dailyLimitWeekendRange,
                    value: Binding(get: { values.weekendMinutes }, set: { model.setWeekendMinutes($0) }),
                    range: RuleMinuteRange.dailyLimit,
                    accessibilityLabel: l10n.dailyLimitSliderWeekend
                )
            }
            RuleRangeLabels()
        }
    }

    private func trustCard(_ values: DailyLimitValues) -> some View {
        NozirCard {
            RuleMinuteSlider(
                title: l10n.trustLadderTitle,
                caption: l10n.trustLadderSubtitle,
                value: Binding(get: { values.trustBonusMinutes }, set: { model.setTrustBonusMinutes($0) }),
                range: RuleMinuteRange.trustLadder,
                accessibilityLabel: l10n.trustLadderSlider,
                valueText: { RuleTexts.trustValue($0, l10n) }
            )
            Text(RuleTexts.trustNote(values.trustBonusMinutes, l10n))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
    }

    /// The way to P10, P12 and P12b. The apps row waits for 2c-2.
    private func otherRules(_ snapshot: RuleSnapshot, isEnabled: Bool) -> some View {
        let session = model.session
        return VStack(alignment: .leading, spacing: NozirSpacing.small) {
            NozirSectionTitle(l10n.rulesOtherLabel)
            NozirCard {
                RuleLinkRow(
                    title: l10n.rulesLinkBedtime,
                    lines: [
                        RuleTexts.bedtimeRange(snapshot.bedtime, l10n),
                        RuleDays.summary(Set(snapshot.bedtime.activeDays), l10n)
                    ],
                    isEnabled: isEnabled
                ) { onOpen(.bedtime(session)) }
                Divider()
                RuleLinkRow(title: l10n.rulesLinkBonus, lines: [RuleTexts.bonusRow(snapshot, l10n)], isEnabled: isEnabled) {
                    onOpen(.bonus(session))
                }
                Divider()
                RuleLinkRow(
                    title: l10n.rulesLinkLocation,
                    lines: [RuleTexts.locationRow(snapshot.locationTracking, l10n)],
                    isEnabled: isEnabled
                ) { onOpen(.locationTracking(session)) }
            }
        }
    }
}
