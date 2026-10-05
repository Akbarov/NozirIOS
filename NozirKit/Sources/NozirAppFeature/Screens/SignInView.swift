import SwiftUI
import NozirDesignSystem

/// P02 as Android `SignInChoiceStep` + `TelegramCodeStep`, Telegram only.
struct SignInView: View {
    @State private var model: SignInModel
    @Environment(\.openURL) private var openURL

    init(model: SignInModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch model.stage {
                case .choice:
                    choice
                case .telegramCode:
                    codeStep
                }
                NozirPrivacyNote(Copy.SignIn.privacyNote)
                    .padding(.top, NozirSpacing.extraLarge)
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
    }

    private var choice: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Copy.SignIn.title).nozirText(.titleLarge)
            Text(model.isTelegramAvailable ? Copy.SignIn.subtitleTelegramOnly : Copy.SignIn.subtitleNoWayIn)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .padding(.top, NozirSpacing.extraSmall)
            if model.isTelegramAvailable {
                NozirButton(Copy.SignIn.telegramButton, isLoading: model.isBusy) {
                    Task {
                        if let link = await model.chooseTelegram() { open(link) }
                    }
                }
                .padding(.top, NozirSpacing.large)
                Text(Copy.SignIn.telegramWhy)
                    .nozirText(.bodySmall, color: NozirColor.textTertiary)
                    .padding(.top, NozirSpacing.small)
            }
            if let message = model.message {
                NozirInlineMessage(message).padding(.top, NozirSpacing.medium)
            }
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Copy.SignIn.codeTitle).nozirText(.titleLarge)
            Text(Copy.SignIn.codeSubtitle(minutes: model.codeMinutes))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .padding(.top, NozirSpacing.extraSmall)
            NozirCodeField(
                code: Binding(get: { model.code }, set: { model.updateCode($0) }),
                placeholder: Copy.SignIn.codePlaceholder
            )
            .padding(.top, NozirSpacing.large)
            if let message = model.message {
                NozirInlineMessage(message).padding(.top, NozirSpacing.small)
            }
            NozirButton(Copy.SignIn.verify, size: .callToAction, isLoading: model.isBusy) {
                Task { await model.verify() }
            }
            // Not `canVerify`: that is false while busy and would grey the button;
            // NozirButton already blocks taps while it shows the spinner.
            .disabled(model.code.count != model.codeLength)
            .padding(.top, NozirSpacing.large)
            NozirButton(Copy.SignIn.openBotAgain, variant: .secondary) {
                if let link = model.botLink { open(link) }
            }
            .padding(.top, NozirSpacing.small)
        }
    }

    private func open(_ link: URL) {
        openURL(link) { accepted in
            if !accepted {
                Task { @MainActor in model.telegramDidNotOpen() }
            }
        }
    }
}
