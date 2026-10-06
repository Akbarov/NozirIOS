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
