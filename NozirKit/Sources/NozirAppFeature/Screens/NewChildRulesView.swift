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
        .task { await model.prefill() }
    }

    private var limitSection: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            Text(l10n.newChildRulesLimitLabel).nozirText(.titleSmall)
            minuteSlider(
                title: l10n.dailyLimitSchoolDays,
                caption: l10n.dailyLimitSchoolDaysRange,
                value: $model.schoolDayMinutes,
                accessibility: l10n.dailyLimitSliderSchool
            )
            minuteSlider(
                title: l10n.dailyLimitWeekend,
                caption: l10n.dailyLimitWeekendRange,
                value: $model.weekendMinutes,
                accessibility: l10n.dailyLimitSliderWeekend
            )
            HStack {
                Text(l10n.dailyLimitRangeMin)
                Spacer()
                Text(l10n.dailyLimitRangeMax)
            }
            .nozirText(.label, color: NozirColor.textTertiary)
        }
    }

    private func minuteSlider(title: String, caption: String, value: Binding<Int>, accessibility: String) -> some View {
        VStack(alignment: .leading, spacing: NozirSpacing.extraSmall) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).nozirText(.body)
                    Text(caption).nozirText(.bodySmall, color: NozirColor.textTertiary)
                }
                Spacer()
                Text(Durations.short(value.wrappedValue, l10n)).nozirText(.titleSmall, color: NozirColor.primaryAccent)
            }
            // Android `RuleMinuteRange.DAILY_LIMIT`: 30…360 in steps of 15.
            Slider(
                value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }),
                in: Durations.range(30...360, including: value.wrappedValue),
                step: 15
            )
            .tint(NozirColor.primary)
            .accessibilityLabel(accessibility)
            .accessibilityValue(Durations.long(value.wrappedValue, l10n))
        }
    }

    private var bedtimeSection: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            Text(l10n.newChildRulesBedtimeLabel).nozirText(.titleSmall)
            HStack(spacing: NozirSpacing.medium) {
                timePicker(l10n.bedtimeStartLabel, $model.bedtimeStart)
                timePicker(l10n.bedtimeEndLabel, $model.bedtimeEnd)
            }
            Text(l10n.bedtimeLength(Durations.long(model.bedtime.lengthMinutes, l10n)))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
            Text(l10n.bedtimeDaysLabel).nozirText(.body)
            HStack(spacing: NozirSpacing.extraSmall) {
                ForEach(1...7, id: \.self) { day in dayChip(day) }
            }
            Text(NewChildRulesModel.daysSummary(model.activeDays, l10n))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
            if model.activeDays.count == 1 {
                Text(l10n.bedtimeDaysHint).nozirText(.bodySmall, color: NozirColor.textTertiary)
            }
            Toggle(isOn: Binding(get: { model.isWindDownOn }, set: { model.setWindDown(on: $0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.bedtimeWindDownTitle).nozirText(.body)
                    Text(model.isWindDownOn ? l10n.bedtimeWindDownSubtitle(model.windDownMinutes) : l10n.bedtimeWindDownOff)
                        .nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
            }
            .tint(NozirColor.primary)
            if model.isWindDownOn {
                // Android `RuleMinuteRange.WIND_DOWN`: 15…60 in steps of 15.
                Slider(
                    value: Binding(get: { Double(model.windDownMinutes) }, set: { model.setWindDownMinutes(Int($0.rounded())) }),
                    in: Durations.range(15...60, including: model.windDownMinutes),
                    step: 15
                )
                .tint(NozirColor.primary)
                .accessibilityLabel(l10n.bedtimeWindDownSlider)
            }
        }
    }

    private func timePicker(_ title: String, _ time: Binding<ClockTime>) -> some View {
        VStack(alignment: .leading, spacing: NozirSpacing.extraSmall) {
            Text(title).nozirText(.bodySmall, color: NozirColor.textSecondary)
            DatePicker(
                title,
                selection: Binding(get: { time.wrappedValue.date() }, set: { time.wrappedValue = ClockTime(date: $0) }),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayChip(_ day: Int) -> some View {
        let isOn = model.activeDays.contains(day)
        return Button {
            model.toggleDay(day)
        } label: {
            Text(l10n.weekdayNamesShort[day - 1])
                .nozirText(.bodySmall, color: isOn ? NozirColor.onPrimary : NozirColor.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(RoundedRectangle(cornerRadius: NozirRadius.button).fill(isOn ? NozirColor.primary : NozirColor.track))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n.weekdayNames[day - 1])
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
