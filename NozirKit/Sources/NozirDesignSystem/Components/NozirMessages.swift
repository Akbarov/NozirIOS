import SwiftUI

/// Android `NozirInlineMessage`: one sentence under a field or a button.
public struct NozirInlineMessage: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .nozirText(.bodySmall, color: NozirColor.actionContent)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Android `NozirBulletRow`: a tick in a soft green disc, then the text.
public struct NozirBulletRow: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: NozirSpacing.compact) {
            Text("✓")
                .nozirText(.label, color: NozirColor.goodContent)
                .frame(width: NozirSize.icon, height: NozirSize.icon)
                .background(Circle().fill(NozirColor.goodContainer))
                .accessibilityHidden(true)
            Text(text).nozirText(.body)
        }
    }
}

/// Android `SignInPrivacyNote`: a lock and one reassuring sentence.
public struct NozirPrivacyNote: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(alignment: .top, spacing: NozirSpacing.small) {
            Text("🔒")
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .accessibilityHidden(true)
            Text(text).nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
        .padding(NozirSpacing.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NozirRadius.cardCompact).fill(NozirColor.divider))
    }
}
