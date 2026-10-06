import SwiftUI
import NozirDesignSystem
import NozirL10n

/// P02 as Android `SignInChoiceStep` + `TelegramCodeStep`, Telegram only.
struct SignInView: View {
    @State private var model: SignInModel
    @Environment(\.openURL) private var openURL
    @Environment(\.l10n) private var l10n
    @State private var toast: String?

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
                NozirPrivacyNote(l10n.signInPrivacyNote)
                    .padding(.top, NozirSpacing.extraLarge)
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .nozirToast($toast)
    }

    private var choice: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(l10n.signInChoiceTitle).nozirText(.titleLarge)
            Text(model.isTelegramAvailable ? l10n.signInChoiceSubtitleTelegramOnly : l10n.signInChoiceSubtitleNoWayIn)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .padding(.top, NozirSpacing.extraSmall)
            if model.isTelegramAvailable {
                NozirButton(l10n.signInActionTelegram, isLoading: model.isBusy) {
                    Task {
                        if let link = await model.chooseTelegram() { open(link) }
                    }
                }
                .padding(.top, NozirSpacing.large)
                Text(l10n.signInTelegramWhy)
                    .nozirText(.bodySmall, color: NozirColor.textTertiary)
                    .padding(.top, NozirSpacing.small)
            }
            if let message = model.message {
                NozirInlineMessage(message.text(l10n)).padding(.top, NozirSpacing.medium)
            }
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(l10n.signInTelegramCodeTitle).nozirText(.titleLarge)
            Text(l10n.signInTelegramCodeSubtitle(model.codeMinutes))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .padding(.top, NozirSpacing.extraSmall)
            NozirCodeField(
                code: Binding(get: { model.code }, set: { model.updateCode($0) }),
                placeholder: l10n.signInCodePlaceholder
            )
            .padding(.top, NozirSpacing.large)
            if let message = model.message {
                NozirInlineMessage(message.text(l10n)).padding(.top, NozirSpacing.small)
            }
            NozirButton(l10n.signInActionVerify, size: .callToAction, isLoading: model.isBusy) {
                Task { await model.verify() }
            }
            // Not `canVerify`: that is false while busy and would grey the button;
            // NozirButton already blocks taps while it shows the spinner.
            .disabled(model.code.count != model.codeLength)
            .padding(.top, NozirSpacing.large)
            NozirButton(l10n.signInActionOpenBotAgain, variant: .secondary) {
                if let link = model.botLink { open(link) }
            }
            .padding(.top, NozirSpacing.small)
        }
    }

    private func open(_ link: URL) {
        openURL(link) { accepted in
            if !accepted {
                Task { @MainActor in toast = l10n.signInTelegramNotOpenedOnlyDoor }
            }
        }
    }
}
