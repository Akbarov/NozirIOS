import SwiftUI
import NozirDesignSystem
import NozirL10n

/// The end of every rules screen: what the last save did, and "Saqlash",
/// enabled only when there is something to save.
struct RuleSaveFooter: View {
    private let notice: RuleNotice?
    private let message: UserMessage?
    private let childName: String?
    private let isSaving: Bool
    private let canSave: Bool
    private let onSave: () -> Void
    @Environment(\.l10n) private var l10n

    init(notice: RuleNotice?, message: UserMessage?, childName: String?, isSaving: Bool, canSave: Bool, onSave: @escaping () -> Void) {
        self.notice = notice
        self.message = message
        self.childName = childName
        self.isSaving = isSaving
        self.canSave = canSave
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            switch notice {
            case .saved?:
                Text(RuleTexts.saved(childName: childName, l10n)).nozirText(.bodySmall, color: NozirColor.goodContent)
            case .conflict?:
                NozirInlineMessage(l10n.rulesConflictNotice)
            case nil:
                EmptyView()
            }
            if let message {
                NozirInlineMessage(message.text(l10n))
            }
            NozirButton(l10n.rulesActionSave, size: .callToAction, isLoading: isSaving, action: onSave)
                .disabled(!canSave && !isSaving)
        }
    }
}

/// A row that leads to another rules screen and states the rule as it stands.
/// Disabled (a frozen child) it still says what the rule is.
struct RuleLinkRow: View {
    private let title: String
    private let lines: [String]
    private let isEnabled: Bool
    private let action: () -> Void

    init(title: String, lines: [String], isEnabled: Bool, action: @escaping () -> Void) {
        self.title = title
        self.lines = lines
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: NozirSpacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).nozirText(.body)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).nozirText(.bodySmall, color: NozirColor.textSecondary)
                    }
                }
                Spacer(minLength: NozirSpacing.small)
                if isEnabled {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(NozirColor.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: NozirSize.control)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
