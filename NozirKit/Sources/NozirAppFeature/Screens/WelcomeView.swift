import SwiftUI
import NozirDesignSystem
import NozirL10n

/// P01, laid out as Android `WelcomeScreen`: the promise centred, the actions at the bottom.
struct WelcomeView: View {
    let onStart: () -> Void
    let onSignIn: () -> Void
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    promise
                        .padding(.horizontal, NozirSpacing.extraLarge)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            VStack(spacing: NozirSpacing.small) {
                NozirButton(l10n.welcomeActionStart, size: .callToAction, action: onStart)
                NozirButton(l10n.welcomeActionHaveAccount, variant: .ghost, action: onSignIn)
            }
            .padding(.horizontal, NozirSpacing.medium)
            .padding(.bottom, NozirSpacing.extraLarge)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var promise: some View {
        VStack(alignment: .leading, spacing: 0) {
            NozirLogoMark(accessibilityLabel: l10n.contentDescriptionLogo)
            Text(l10n.welcomeTitle)
                .nozirText(.headline)
                .padding(.top, NozirSpacing.large)
            Text(l10n.welcomeBody)
                .nozirText(.body, color: NozirColor.textSecondary)
                .padding(.top, NozirSpacing.compact)
            VStack(alignment: .leading, spacing: NozirSpacing.compact) {
                NozirBulletRow(l10n.welcomeBenefitSummary)
                NozirBulletRow(l10n.welcomeBenefitScreenTime)
                NozirBulletRow(l10n.welcomeBenefitLocation)
            }
            .padding(.top, NozirSpacing.extraLarge)
        }
    }
}

#Preview {
    WelcomeView(onStart: {}, onSignIn: {})
}
