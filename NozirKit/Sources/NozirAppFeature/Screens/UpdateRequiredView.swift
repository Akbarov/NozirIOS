import SwiftUI
import NozirDesignSystem
import NozirL10n

/// Android `UpdateRequiredScreen`: update, and the emergency number stays one tap away.
struct UpdateRequiredView: View {
    let emergencyNumber: String?
    let appStoreURL: URL?
    @Environment(\.openURL) private var openURL
    @Environment(\.l10n) private var l10n
    @State private var notice: Notice?

    /// Kept as a meaning, so the sentence follows a language change.
    private enum Notice {
        case storeMissing, dialerMissing
    }

    var body: some View {
        // Scrolls, so the emergency button stays reachable at large text sizes
        // and in landscape; centred while it fits.
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            NozirLogoMark(accessibilityLabel: l10n.contentDescriptionLogo)
            Text(l10n.updateRequiredTitle)
                .nozirText(.titleLarge)
                .multilineTextAlignment(.center)
                .padding(.top, NozirSpacing.medium)
            Text(l10n.updateRequiredBody)
                .nozirText(.body, color: NozirColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, NozirSpacing.small)
            NozirButton(l10n.updateRequiredAction, size: .callToAction) { openStore() }
                .padding(.top, NozirSpacing.large)
            if let notice {
                NozirInlineMessage(text(for: notice)).padding(.top, NozirSpacing.compact)
            }
            if let emergencyNumber {
                NozirButton(l10n.updateRequiredCallEmergency(emergencyNumber), variant: .criticalOutline) {
                    call(emergencyNumber)
                }
                .padding(.top, NozirSpacing.medium)
            }
        }
        .padding(.horizontal, NozirSpacing.large)
        .padding(.vertical, NozirSpacing.extraLarge)
    }

    private func text(for notice: Notice) -> String {
        switch notice {
        case .storeMissing: l10n.updateRequiredStoreMissing
        case .dialerMissing: l10n.updateRequiredDiallerMissing
        }
    }

    private func openStore() {
        guard let appStoreURL else {
            notice = .storeMissing
            return
        }
        openURL(appStoreURL) { accepted in
            if !accepted {
                Task { @MainActor in notice = .storeMissing }
            }
        }
    }

    private func call(_ number: String) {
        guard let url = URL(string: "tel:\(number)") else {
            notice = .dialerMissing
            return
        }
        openURL(url) { accepted in
            if !accepted {
                Task { @MainActor in notice = .dialerMissing }
            }
        }
    }
}

#Preview {
    UpdateRequiredView(emergencyNumber: "112", appStoreURL: nil)
}
