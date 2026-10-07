import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// The Home "Himoya" row (Android `ProtectionRow`), in the card tone of spec
/// D2. One button for VoiceOver: the title and body say the level; the
/// shield and the chevron are decoration.
struct ProtectionRow: View {
    let level: ProtectionLevel
    let action: () -> Void
    @Environment(\.l10n) private var l10n

    var body: some View {
        Button(action: action) {
            NozirCard(tone: ProtectionTexts.cardTone(level)) {
                HStack(spacing: NozirSpacing.compact) {
                    ProtectionShield(level: level)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ProtectionTexts.homeTitle(level, l10n)).nozirText(.body)
                        Text(ProtectionTexts.homeBody(level, l10n))
                            .nozirText(.bodySmall, color: NozirColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text(l10n.glyphChevron)
                        .nozirText(.titleSmall, color: NozirColor.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// The shield tile; decoration only. Healthy sits on the good colour; on a
/// tinted card the tile is the plain card colour, so it stays visible.
struct ProtectionShield: View {
    let level: ProtectionLevel
    @Environment(\.l10n) private var l10n

    var body: some View {
        Text(l10n.glyphShield)
            .font(.system(size: 18))
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: NozirRadius.cardCompact).fill(tile))
            .accessibilityHidden(true)
    }

    private var tile: Color {
        level == .healthy ? NozirColor.goodContainer : NozirColor.card
    }
}
