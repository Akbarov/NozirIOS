import SwiftUI
import NozirDesignSystem
import NozirL10n

/// Android `SosBanner`: the first thing on P05 while an alarm is unanswered.
/// "N daqiqa oldin" moves on by itself every 30 s.
struct SosBanner: View {
    let alert: SosAlert
    let onOpen: () -> Void
    @Environment(\.l10n) private var l10n

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            NozirCard(tone: .critical) {
                HStack(alignment: .top, spacing: NozirSpacing.compact) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(NozirColor.criticalContent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.title(l10n)).nozirText(.titleSmall, color: NozirColor.criticalContent)
                        Text(alert.when(now: context.date, l10n)).nozirText(.bodySmall, color: NozirColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                NozirButton(l10n.homeSosBannerAction, variant: .criticalOutline, action: onOpen)
            }
        }
    }
}

/// The SOS sheet of this slice: who, when, and two numbers to dial. P15 (map,
/// "I have seen it") comes with its own slice.
struct SosSheet: View {
    let alert: SosAlert
    @Environment(\.l10n) private var l10n
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var dialerMissing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NozirSpacing.large) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        VStack(alignment: .leading, spacing: NozirSpacing.extraSmall) {
                            Text(alert.title(l10n)).nozirText(.titleLarge, color: NozirColor.criticalContent)
                            Text(alert.when(now: context.date, l10n)).nozirText(.body, color: NozirColor.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    VStack(alignment: .leading, spacing: NozirSpacing.small) {
                        NozirButton(alert.callChildTitle(l10n), size: .callToAction) {
                            call(alert.childCallURL)
                        }
                        .disabled(alert.childCallURL == nil)
                        if alert.childCallURL == nil {
                            Text(l10n.sosCallChildUnavailable).nozirText(.bodySmall, color: NozirColor.textSecondary)
                        }
                    }
                    if let emergencyTitle = alert.emergencyTitle(l10n) {
                        NozirButton(emergencyTitle, variant: .criticalOutline, size: .callToAction) {
                            call(alert.emergencyCallURL)
                        }
                    }
                    if dialerMissing {
                        NozirInlineMessage(l10n.updateRequiredDiallerMissing)
                    }
                }
                .padding(NozirSpacing.medium)
            }
            .background(NozirColor.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(l10n.contentDescriptionBack)
                }
            }
        }
    }

    private func call(_ url: URL?) {
        guard let url else {
            dialerMissing = true
            return
        }
        openURL(url) { accepted in
            if !accepted {
                Task { @MainActor in dialerMissing = true }
            }
        }
    }
}
