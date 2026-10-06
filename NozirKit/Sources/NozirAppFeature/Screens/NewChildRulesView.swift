import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P03b as Android `NewChildRulesScreen`: two limits, the night window, the nights.
struct NewChildRulesView: View {
    @State private var model: NewChildRulesModel
    private let onSaved: (Child) -> Void
    @Environment(\.l10n) private var l10n

    init(model: NewChildRulesModel, onSaved: @escaping (Child) -> Void) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                Text(l10n.newChildRulesTitle(model.draft.displayName)).nozirText(.titleLarge)
                Text(model.isPrefilledFromSibling ? l10n.newChildRulesCopied : l10n.newChildRulesIntro)
                    .nozirText(.body, color: NozirColor.textSecondary)
                NozirCard { limitSection }
                NozirCard { bedtimeSection }
                Text(l10n.newChildRulesAppsLater).nozirText(.bodySmall, color: NozirColor.textTertiary)
                if let message = model.message {
                    NozirInlineMessage(message.text(l10n))
                }
                NozirButton(l10n.newChildRulesActionContinue, size: .callToAction, isLoading: model.isSaving) {
                    Task {
                        if let child = await model.save() { onSaved(child) }
                    }
                }
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenNewChildRulesTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Once the child exists, going back and saving again would be a second child.
        .navigationBarBackButtonHidden(model.hasCreatedChild)
        .task { await model.prefill() }
    }

    private var limitSection: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            Text(l10n.newChildRulesLimitLabel).nozirText(.titleSmall)
            RuleMinuteSlider(
                title: l10n.dailyLimitSchoolDays,
                caption: l10n.dailyLimitSchoolDaysRange,
                value: $model.schoolDayMinutes,
                range: RuleMinuteRange.dailyLimit,
                accessibilityLabel: l10n.dailyLimitSliderSchool
            )
            RuleMinuteSlider(
                title: l10n.dailyLimitWeekend,
                caption: l10n.dailyLimitWeekendRange,
                value: $model.weekendMinutes,
                range: RuleMinuteRange.dailyLimit,
                accessibilityLabel: l10n.dailyLimitSliderWeekend
            )
            RuleRangeLabels()
        }
    }

    private var bedtimeSection: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            Text(l10n.newChildRulesBedtimeLabel).nozirText(.titleSmall)
            HStack(spacing: NozirSpacing.medium) {
                RuleTimePicker(l10n.bedtimeStartLabel, time: $model.bedtimeStart)
                RuleTimePicker(l10n.bedtimeEndLabel, time: $model.bedtimeEnd)
            }
            Text(l10n.bedtimeLength(Durations.long(model.bedtime.lengthMinutes, l10n)))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
            RuleDaysSection(activeDays: model.activeDays) { model.toggleDay($0) }
            RuleWindDownSection(
                minutes: model.windDownMinutes,
                onToggle: { model.setWindDown(on: $0) },
                onMinutes: { model.setWindDownMinutes($0) }
            )
        }
    }
}
