import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P04 as Android `PairingScreen`: the code, the same code as a QR, and what
/// the child's phone has done so far.
struct PairingView: View {
    @State private var model: PairingModel
    private let onFinished: () -> Void
    @Environment(\.l10n) private var l10n
    @Environment(\.scenePhase) private var scenePhase

    init(model: PairingModel, onFinished: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onFinished = onFinished
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                Text(l10n.pairingInstruction).nozirText(.body, color: NozirColor.textSecondary)
                if model.isConfirmingReplacement, let device = model.connectedDevice {
                    replaceCard(device)
                }
                codeCard
                if case .waiting(let code) = model.phase {
                    VStack(spacing: NozirSpacing.small) {
                        NozirQRCode(payload: code.qrContent, accessibilityLabel: l10n.pairingQrContentDescription)
                        Text(l10n.pairingQrHint)
                            .nozirText(.bodySmall, color: NozirColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: NozirSpacing.compact) {
                    NozirChecklistRow(l10n.pairingStepAppInstalled, isDone: model.isAppInstalled)
                    NozirChecklistRow(
                        model.phase == .paired ? l10n.pairingStepPaired : l10n.pairingStepWaitingCode,
                        isDone: model.phase == .paired
                    )
                }
                if let message = model.message {
                    NozirInlineMessage(message.text(l10n))
                }
                if model.phase == .paired {
                    NozirButton(l10n.pairingActionOpenHome, size: .callToAction, action: onFinished)
                }
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.pairingTopBar(model.child.displayName))
        .navigationBarTitleDisplayMode(.inline)
        // Restarted when the app comes back to the foreground, cancelled when it
        // leaves or when this screen goes away.
        .task(id: scenePhase == .active) {
            if scenePhase == .active { await model.run() }
        }
    }

    @ViewBuilder
    private var codeCard: some View {
        NozirCard {
            switch model.phase {
            case .loading:
                ProgressView().tint(NozirColor.primary).frame(maxWidth: .infinity)
            case .waiting(let code):
                Text(l10n.pairingCodeLabel).nozirText(.bodySmall, color: NozirColor.textSecondary)
                Text(Self.grouped(code.code))
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .foregroundStyle(NozirColor.textPrimary)
                    .accessibilityLabel(code.code.map(String.init).joined(separator: " "))
                Text(l10n.pairingCodeValidity).nozirText(.bodySmall, color: NozirColor.textTertiary)
            case .noCode:
                Text(l10n.pairingNoCodeTitle).nozirText(.titleSmall)
                Text(l10n.pairingNoCodeBody).nozirText(.bodySmall, color: NozirColor.textSecondary)
                NozirButton(l10n.pairingActionIssueCode, isLoading: model.isBusy) {
                    Task { await model.requestNewCode() }
                }
            case .paired:
                Text(l10n.pairingStepPaired).nozirText(.titleSmall, color: NozirColor.goodContent)
            }
        }
    }

    private func replaceCard(_ device: ChildDevice) -> some View {
        NozirCard(tone: .attention) {
            Text(l10n.pairingReplaceTitle).nozirText(.titleSmall)
            Text(device.isOnline ? l10n.pairingReplaceDeviceOnline(device.label) : l10n.pairingReplaceDeviceOffline(device.label))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
            Text(l10n.pairingReplaceBody).nozirText(.bodySmall)
            HStack(spacing: NozirSpacing.small) {
                NozirButton(l10n.pairingReplaceCancel, variant: .secondary) { model.dismissReplacement() }
                NozirButton(l10n.pairingReplaceConfirm, isLoading: model.isBusy) {
                    Task { await model.confirmReplacement() }
                }
            }
        }
    }

    /// "472918" → "472 918", easier to read out to a child.
    static func grouped(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return String(code.prefix(3)) + " " + String(code.suffix(3))
    }
}
