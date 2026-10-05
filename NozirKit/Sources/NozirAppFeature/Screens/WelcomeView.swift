import SwiftUI
import NozirDesignSystem

/// P01, laid out as Android `WelcomeScreen`: the promise centred, the actions at the bottom.
struct WelcomeView: View {
    let onStart: () -> Void
    let onSignIn: () -> Void

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
                NozirButton(Copy.Welcome.start, size: .callToAction, action: onStart)
                NozirButton(Copy.Welcome.haveAccount, variant: .ghost, action: onSignIn)
            }
            .padding(.horizontal, NozirSpacing.medium)
            .padding(.bottom, NozirSpacing.extraLarge)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var promise: some View {
        VStack(alignment: .leading, spacing: 0) {
            NozirLogoMark(accessibilityLabel: Copy.Welcome.logoDescription)
            Text(Copy.Welcome.title)
                .nozirText(.headline)
                .padding(.top, NozirSpacing.large)
            Text(Copy.Welcome.body)
                .nozirText(.body, color: NozirColor.textSecondary)
                .padding(.top, NozirSpacing.compact)
            VStack(alignment: .leading, spacing: NozirSpacing.compact) {
                NozirBulletRow(Copy.Welcome.benefitSummary)
                NozirBulletRow(Copy.Welcome.benefitScreenTime)
                NozirBulletRow(Copy.Welcome.benefitLocation)
            }
            .padding(.top, NozirSpacing.extraLarge)
        }
    }
}

#Preview {
    WelcomeView(onStart: {}, onSignIn: {})
}
