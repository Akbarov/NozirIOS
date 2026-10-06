import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// A quarter-hour slider under its title, the value on the right (P03b, P09, P12).
struct RuleMinuteSlider: View {
    private let title: String
    private let caption: String?
    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let accessibilityLabel: String
    /// The value as shown; nil writes it as "2s 30d".
    private let valueText: ((Int) -> String)?
    @Environment(\.l10n) private var l10n

    init(
        title: String,
        caption: String? = nil,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        accessibilityLabel: String,
        valueText: ((Int) -> String)? = nil
    ) {
        self.title = title
        self.caption = caption
        _value = value
        self.range = range
        self.accessibilityLabel = accessibilityLabel
        self.valueText = valueText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.extraSmall) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).nozirText(.body)
                    if let caption {
                        Text(caption).nozirText(.bodySmall, color: NozirColor.textTertiary)
                    }
                }
                Spacer()
                Text(valueText?(value) ?? Durations.short(value, l10n)).nozirText(.titleSmall, color: NozirColor.primaryAccent)
            }
            // A value from elsewhere stretches the range rather than being moved by it.
            Slider(
                value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                in: Durations.range(range, including: value),
                step: Double(RuleMinuteRange.step)
            )
            .tint(NozirColor.primary)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(valueText?(value) ?? Durations.long(value, l10n))
        }
    }
}

/// "30d … 6s" under the daily-limit sliders.
struct RuleRangeLabels: View {
    @Environment(\.l10n) private var l10n

    var body: some View {
        HStack {
            Text(l10n.dailyLimitRangeMin)
            Spacer()
            Text(l10n.dailyLimitRangeMax)
        }
        .nozirText(.label, color: NozirColor.textTertiary)
    }
}

/// A wall-clock time with its label above (bedtime start or end).
struct RuleTimePicker: View {
    private let title: String
    @Binding private var time: ClockTime

    init(_ title: String, time: Binding<ClockTime>) {
        self.title = title
        _time = time
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.extraSmall) {
            Text(title).nozirText(.bodySmall, color: NozirColor.textSecondary)
            DatePicker(
                title,
                selection: Binding(get: { time.date() }, set: { time = ClockTime(date: $0) }),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The seven nights as chips, what they add up to, and the hint when one is left.
struct RuleDaysSection: View {
    private let activeDays: Set<Int>
    private let onToggle: (Int) -> Void
    @Environment(\.l10n) private var l10n

    init(activeDays: Set<Int>, onToggle: @escaping (Int) -> Void) {
        self.activeDays = activeDays
        self.onToggle = onToggle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            Text(l10n.bedtimeDaysLabel).nozirText(.body)
            HStack(spacing: NozirSpacing.extraSmall) {
                ForEach(1...7, id: \.self) { day in chip(day) }
            }
            Text(RuleDays.summary(activeDays, l10n)).nozirText(.bodySmall, color: NozirColor.textSecondary)
            if activeDays.count == 1 {
                Text(l10n.bedtimeDaysHint).nozirText(.bodySmall, color: NozirColor.textTertiary)
            }
        }
    }

    private func chip(_ day: Int) -> some View {
        let isOn = activeDays.contains(day)
        return Button {
            onToggle(day)
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

/// The warning before bedtime: a switch, and while it is on, its length.
/// Off is 0 — the only shape the child's phone understands.
struct RuleWindDownSection: View {
    private let minutes: Int
    private let onToggle: (Bool) -> Void
    private let onMinutes: (Int) -> Void
    @Environment(\.l10n) private var l10n

    init(minutes: Int, onToggle: @escaping (Bool) -> Void, onMinutes: @escaping (Int) -> Void) {
        self.minutes = minutes
        self.onToggle = onToggle
        self.onMinutes = onMinutes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            Toggle(isOn: Binding(get: { minutes > 0 }, set: { onToggle($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.bedtimeWindDownTitle).nozirText(.body)
                    Text(minutes > 0 ? l10n.bedtimeWindDownSubtitle(minutes) : l10n.bedtimeWindDownOff)
                        .nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
            }
            .tint(NozirColor.primary)
            if minutes > 0 {
                Slider(
                    value: Binding(get: { Double(minutes) }, set: { onMinutes(Int($0.rounded())) }),
                    in: Durations.range(RuleMinuteRange.windDown, including: minutes),
                    step: Double(RuleMinuteRange.step)
                )
                .tint(NozirColor.primary)
                .accessibilityLabel(l10n.bedtimeWindDownSlider)
            }
        }
    }
}
