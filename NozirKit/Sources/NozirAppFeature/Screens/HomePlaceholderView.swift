import SwiftUI
import NozirDesignSystem

/// Stands in for P05 until the next sub-project builds it.
struct HomePlaceholderView: View {
    let onSignOut: () -> Void

    var body: some View {
        VStack(spacing: NozirSpacing.medium) {
            NozirLogoMark(accessibilityLabel: Copy.Welcome.logoDescription)
            Text(Copy.Home.title).nozirText(.titleLarge)
            Text(Copy.Home.body)
                .nozirText(.body, color: NozirColor.textSecondary)
                .multilineTextAlignment(.center)
            NozirButton(Copy.Home.signOut, variant: .secondary, action: onSignOut)
                .padding(.top, NozirSpacing.large)
        }
        .padding(.horizontal, NozirSpacing.large)
    }
}
