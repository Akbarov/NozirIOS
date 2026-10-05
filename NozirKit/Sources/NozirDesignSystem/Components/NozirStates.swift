import SwiftUI

/// Android `NozirErrorState`: what went wrong, and one way to try again.
public struct NozirErrorState: View {
    private let title: String
    private let message: String
    private let retryTitle: String
    private let onRetry: () -> Void

    public init(title: String, message: String, retryTitle: String, onRetry: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: NozirSpacing.compact) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(NozirColor.actionContent)
                .accessibilityHidden(true)
            Text(title)
                .nozirText(.titleSmall)
                .multilineTextAlignment(.center)
            Text(message)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .multilineTextAlignment(.center)
            NozirButton(retryTitle, variant: .secondary, action: onRetry)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NozirSpacing.extraLarge)
    }
}

/// Android `NozirEmptyState`: nothing yet is an answer, not an error.
public struct NozirEmptyState: View {
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: NozirSpacing.compact) {
            Text(title)
                .nozirText(.titleSmall)
                .multilineTextAlignment(.center)
            Text(message)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                NozirButton(actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NozirSpacing.extraLarge)
    }
}

/// Android `NozirOfflineNotice`: the screen shows the last known state.
public struct NozirOfflineNotice: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: NozirSpacing.small) {
            Image(systemName: "wifi.slash")
                .accessibilityHidden(true)
            Text(text)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
        .foregroundStyle(NozirColor.textSecondary)
        .padding(.horizontal, NozirSpacing.compact)
        .padding(.vertical, NozirSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NozirRadius.cardCompact).fill(NozirColor.track))
    }
}
