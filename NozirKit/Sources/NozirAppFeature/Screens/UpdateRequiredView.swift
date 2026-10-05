import SwiftUI
import NozirDesignSystem

/// Android `UpdateRequiredScreen`: update, and the emergency number stays one tap away.
struct UpdateRequiredView: View {
    let emergencyNumber: String?
    let appStoreURL: URL?
    @Environment(\.openURL) private var openURL
    @State private var message: String?

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
            NozirLogoMark(accessibilityLabel: Copy.Welcome.logoDescription)
            Text(Copy.Update.title)
                .nozirText(.titleLarge)
                .multilineTextAlignment(.center)
                .padding(.top, NozirSpacing.medium)
            Text(Copy.Update.body)
                .nozirText(.body, color: NozirColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, NozirSpacing.small)
            NozirButton(Copy.Update.action, size: .callToAction) { openStore() }
                .padding(.top, NozirSpacing.large)
            if let message {
                NozirInlineMessage(message).padding(.top, NozirSpacing.compact)
            }
            if let emergencyNumber {
                NozirButton(Copy.Update.callEmergency(emergencyNumber), variant: .criticalOutline) {
                    call(emergencyNumber)
                }
                .padding(.top, NozirSpacing.medium)
            }
        }
        .padding(.horizontal, NozirSpacing.large)
        .padding(.vertical, NozirSpacing.extraLarge)
    }

    private func openStore() {
        guard let appStoreURL else {
            message = Copy.Update.storeMissing
            return
        }
        openURL(appStoreURL) { accepted in
            if !accepted {
                Task { @MainActor in message = Copy.Update.storeMissing }
            }
        }
    }

    private func call(_ number: String) {
        guard let url = URL(string: "tel:\(number)") else {
            message = Copy.Update.dialerMissing
            return
        }
        openURL(url) { accepted in
            if !accepted {
                Task { @MainActor in message = Copy.Update.dialerMissing }
            }
        }
    }
}

#Preview {
    UpdateRequiredView(emergencyNumber: "112", appStoreURL: nil)
}
