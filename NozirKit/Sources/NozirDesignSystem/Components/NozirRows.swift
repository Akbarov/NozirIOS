import SwiftUI

public enum NozirStatusLevel: Sendable {
    case good, attention, action, critical
}

/// A small coloured dot beside a status label; the label carries the meaning.
public struct NozirStatusDot: View {
    private let level: NozirStatusLevel

    public init(_ level: NozirStatusLevel) {
        self.level = level
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch level {
        case .good: NozirColor.goodContent
        case .attention: NozirColor.attentionContent
        case .action: NozirColor.actionContent
        case .critical: NozirColor.criticalContent
        }
    }
}

public struct NozirSectionTitle: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .nozirText(.titleSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A tappable settings line: title, the current value, a chevron.
public struct NozirSettingsRow: View {
    private let title: String
    private let value: String?
    private let action: () -> Void

    public init(_ title: String, value: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.value = value
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: NozirSpacing.small) {
                Text(title).nozirText(.body)
                Spacer(minLength: NozirSpacing.small)
                if let value {
                    Text(value).nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(NozirColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: NozirSize.control)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One step of P04's checklist: done steps are ticked.
public struct NozirChecklistRow: View {
    private let text: String
    private let isDone: Bool

    public init(_ text: String, isDone: Bool) {
        self.text = text
        self.isDone = isDone
    }

    public var body: some View {
        HStack(spacing: NozirSpacing.compact) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? NozirColor.goodContent : NozirColor.textTertiary)
                .accessibilityHidden(true)
            Text(text).nozirText(.body, color: isDone ? NozirColor.textPrimary : NozirColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }
}
