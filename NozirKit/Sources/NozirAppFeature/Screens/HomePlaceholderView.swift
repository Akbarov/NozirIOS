import SwiftUI
import NozirDesignSystem
import NozirL10n

/// Stands in for P05 until sub-project 2b builds it.
struct HomePlaceholderView: View {
    var onSignOut: (() -> Void)?
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(spacing: NozirSpacing.medium) {
            NozirLogoMark(accessibilityLabel: l10n.contentDescriptionLogo)
            Text(l10n.iosHomePlaceholderTitle).nozirText(.titleLarge)
            Text(l10n.iosHomePlaceholderBody)
                .nozirText(.body, color: NozirColor.textSecondary)
                .multilineTextAlignment(.center)
            if let onSignOut {
                NozirButton(l10n.profileActionSignOut, variant: .secondary, action: onSignOut)
                    .padding(.top, NozirSpacing.large)
            }
        }
        .padding(.horizontal, NozirSpacing.large)
    }
}
